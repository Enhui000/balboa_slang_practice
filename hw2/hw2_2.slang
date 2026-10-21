import raster_common;
[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float2 sp0, // vertex at screen space
                  uniform float2 sp1,
                  uniform float2 sp2,
                  uniform float inv_depth0, // inverse depth in camera space
                  uniform float inv_depth1,
                  uniform float inv_depth2,
                  uniform int2 aabb_min,
                  uniform float3 c0, // vertex color
                  uniform float3 c1,
                  uniform float3 c2,
                  uniform float s,
                  uniform float a,
                  RWTexture2D<float4> color_image,
                  RWTexture2D<float> depth_image) {
    int2 ipixel = int2(tid) + int2(aabb_min);
    uint width, height;
    color_image.GetDimensions(width, height);
    if (ipixel.x < 0 || ipixel.y < 0 || ipixel.x >= width || ipixel.y >= height) {
        return;
    }

    float3 b_prime;
    if (!barycentric(float2(ipixel)+0.5, sp0, sp1, sp2, b_prime)) return;
    float3 b = b_prime * float3(inv_depth0, inv_depth1, inv_depth2);
    float inv_depth = b.x+b.y+b.z;
    if (inv_depth <= 0) return;
    float depth = 1.0/inv_depth;
    if (depth >= depth_image[ipixel]) return;
    b /= inv_depth;
    depth_image[ipixel] = depth;
    color_image[ipixel] = float4(b.x*c0+b.y*c1+b.z*c2, 1.0);
}
