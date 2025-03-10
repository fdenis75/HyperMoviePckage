#include <metal_stdlib>
using namespace metal;

// Kernel for scaling images with high-quality bilinear filtering
kernel void scaleTexture(texture2d<float, access::read> inputTexture [[texture(0)]],
                         texture2d<float, access::write> outputTexture [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    // Check if we're within the output texture bounds
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Calculate normalized coordinates
    float2 inputSize = float2(inputTexture.get_width(), inputTexture.get_height());
    float2 outputSize = float2(outputTexture.get_width(), outputTexture.get_height());
    float2 normalizedCoord = float2(gid) / outputSize;
    
    // Sample input texture with bilinear filtering
    float2 readCoord = normalizedCoord * inputSize;
    uint2 readCoordInt = uint2(readCoord);
    float2 fraction = fract(readCoord);
    
    // Read the four surrounding pixels
    float4 colorTL = inputTexture.read(readCoordInt);
    float4 colorTR = inputTexture.read(uint2(min(readCoordInt.x + 1, uint(inputSize.x - 1)), readCoordInt.y));
    float4 colorBL = inputTexture.read(uint2(readCoordInt.x, min(readCoordInt.y + 1, uint(inputSize.y - 1))));
    float4 colorBR = inputTexture.read(uint2(min(readCoordInt.x + 1, uint(inputSize.x - 1)), 
                                            min(readCoordInt.y + 1, uint(inputSize.y - 1))));
    
    // Bilinear interpolation
    float4 colorT = mix(colorTL, colorTR, fraction.x);
    float4 colorB = mix(colorBL, colorBR, fraction.x);
    float4 finalColor = mix(colorT, colorB, fraction.y);
    
    outputTexture.write(finalColor, gid);
}

// Kernel for compositing images onto a canvas
kernel void compositeTextures(texture2d<float, access::read> sourceTexture [[texture(0)]],
                              texture2d<float, access::read_write> destinationTexture [[texture(1)]],
                              constant uint2 *position [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    // Check if we're within the source texture bounds
    if (gid.x >= sourceTexture.get_width() || gid.y >= sourceTexture.get_height()) {
        return;
    }
    
    // Calculate destination position
    uint2 destPos = gid + *position;
    
    // Check if we're within the destination texture bounds
    if (destPos.x >= destinationTexture.get_width() || destPos.y >= destinationTexture.get_height()) {
        return;
    }
    
    // Read source pixel
    float4 sourceColor = sourceTexture.read(gid);
    
    // Write to destination
    destinationTexture.write(sourceColor, destPos);
}

// Kernel for adding timestamp overlay
kernel void addTimestamp(texture2d<float, access::read_write> texture [[texture(0)]],
                         constant uint2 *position [[buffer(0)]],
                         constant uint2 *size [[buffer(1)]],
                         constant float4 *backgroundColor [[buffer(2)]],
                         constant float4 *textColor [[buffer(3)]],
                         constant uchar *timestampData [[buffer(4)]],
                         constant uint *timestampLength [[buffer(5)]],
                         uint2 gid [[thread_position_in_grid]]) {
    // Check if we're within the timestamp area
    uint2 timestampPos = *position;
    uint2 timestampSize = *size;
    
    if (gid.x < timestampPos.x || gid.x >= (timestampPos.x + timestampSize.x) ||
        gid.y < timestampPos.y || gid.y >= (timestampPos.y + timestampSize.y)) {
        return;
    }
    
    // Draw background with semi-transparency
    float4 existingColor = texture.read(gid);
    float4 bgColor = *backgroundColor;
    
    // Simple alpha blending
    float4 blendedColor = float4(
        mix(existingColor.rgb, bgColor.rgb, bgColor.a),
        max(existingColor.a, bgColor.a)
    );
    
    texture.write(blendedColor, gid);
    
    // Note: Text rendering would be implemented separately using a texture atlas
    // This is a simplified version that just draws the background
}

// Kernel for filling a texture with a solid color
kernel void fillTexture(texture2d<float, access::write> texture [[texture(0)]],
                        constant float4 *color [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
    // Check if we're within the texture bounds
    if (gid.x >= texture.get_width() || gid.y >= texture.get_height()) {
        return;
    }
    
    // Fill with color
    texture.write(*color, gid);
}

// Kernel for adding border to an image
kernel void addBorder(texture2d<float, access::read_write> texture [[texture(0)]],
                      constant uint2 *position [[buffer(0)]],
                      constant uint2 *size [[buffer(1)]],
                      constant float4 *borderColor [[buffer(2)]],
                      constant float *borderWidth [[buffer(3)]],
                      uint2 gid [[thread_position_in_grid]]) {
    // Check if we're within the texture bounds
    if (gid.x >= texture.get_width() || gid.y >= texture.get_height()) {
        return;
    }
    
    uint2 pos = *position;
    uint2 sz = *size;
    float width = *borderWidth;
    
    // Check if the pixel is on the border
    bool isBorder = false;
    
    if (gid.x >= pos.x && gid.x < (pos.x + sz.x) &&
        gid.y >= pos.y && gid.y < (pos.y + sz.y)) {
        
        float distanceFromLeft = float(gid.x - pos.x);
        float distanceFromRight = float(pos.x + sz.x - 1 - gid.x);
        float distanceFromTop = float(gid.y - pos.y);
        float distanceFromBottom = float(pos.y + sz.y - 1 - gid.y);
        
        isBorder = (distanceFromLeft < width || 
                   distanceFromRight < width || 
                   distanceFromTop < width || 
                   distanceFromBottom < width);
    }
    
    if (isBorder) {
        texture.write(*borderColor, gid);
    }
}

// Kernel for adding shadow effect
kernel void addShadow(texture2d<float, access::read> sourceTexture [[texture(0)]],
                      texture2d<float, access::write> outputTexture [[texture(1)]],
                      constant uint2 *position [[buffer(0)]],
                      constant uint2 *size [[buffer(1)]],
                      constant float4 *shadowColor [[buffer(2)]],
                      constant float2 *shadowOffset [[buffer(3)]],
                      constant float *shadowRadius [[buffer(4)]],
                      uint2 gid [[thread_position_in_grid]]) {
    // Check if we're within the output texture bounds
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    uint2 pos = *position;
    uint2 sz = *size;
    float2 offset = *shadowOffset;
    float radius = *shadowRadius;
    
    // Calculate shadow position
    uint2 shadowPos = uint2(pos.x + uint(offset.x), pos.y + uint(offset.y));
    
    // Check if the pixel is within the shadow area
    if (gid.x >= shadowPos.x && gid.x < (shadowPos.x + sz.x) &&
        gid.y >= shadowPos.y && gid.y < (shadowPos.y + sz.y)) {
        
        // Simple shadow implementation (without blur for now)
        outputTexture.write(*shadowColor, gid);
    }
    
    // Copy the source image on top of the shadow
    if (gid.x >= pos.x && gid.x < (pos.x + sz.x) &&
        gid.y >= pos.y && gid.y < (pos.y + sz.y)) {
        
        uint2 sourcePos = uint2(gid.x - pos.x, gid.y - pos.y);
        
        // Check if we're within the source texture bounds
        if (sourcePos.x < sourceTexture.get_width() && sourcePos.y < sourceTexture.get_height()) {
            float4 color = sourceTexture.read(sourcePos);
            outputTexture.write(color, gid);
        }
    }
} 