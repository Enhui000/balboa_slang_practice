import raster_common;
[shader("compute")]
[numthreads(64, 1, 1)]
void clear_buffers(uint tid : SV_DispatchThreadID,
                   uniform uint num_pixels,
                   RWStructuredBuffer<uint> depth_buffer,
                   RWStructuredBuffer<uint> triangle_id_buffer) {
    if (tid >= num_pixels)
        return;

    depth_buffer[tid] = 0xffffffff;
    triangle_id_buffer[tid] = 0xffffffff;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void transform_vertices(
    uint tid : SV_DispatchThreadID,
    uniform uint num_vertices,
    uniform uint vertex_offset,
    uniform float4x4 MVP,
    StructuredBuffer<float3> vertices,
    RWStructuredBuffer<float3> projected_vertices)
{
    if (tid >= num_vertices)
        return;

    uint i = vertex_offset + tid;
    float4 p = mul(MVP, float4(vertices[i], 1.0));
    projected_vertices[i] = p.xyz / p.w;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void rasterize_depth(
        uint tid : SV_DispatchThreadID,
        uniform uint num_triangles,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        // A projected vertex store the screen space coordinates
        // in xy, and the inverse depth in z.
        StructuredBuffer<float3> projected_vertices,
        RWStructuredBuffer<uint> depth_buffer) {
    if (tid >= num_triangles) return;
    uint3 face = faces[tid];
    float3 p0 = projected_vertices[face.x];
    float3 p1 = projected_vertices[face.y];
    float3 p2 = projected_vertices[face.z];
    if (min(p0.z,min(p1.z,p2.z)) <= 0) return;
    if (abs(edge_equation(p0.xy,p1.xy,p2.xy)) < 1e-8) return;
    int2 lo = max(int2(floor(min(p0.xy,min(p1.xy,p2.xy)))),int2(0));
    int2 hi = min(int2(ceil(max(p0.xy,max(p1.xy,p2.xy)))),int2(width-1,height-1));
    for (int y=lo.y; y<=hi.y; ++y) for (int x=lo.x; x<=hi.x; ++x) {
        float3 b_prime;
        if (!barycentric(float2(x,y)+0.5,p0.xy,p1.xy,p2.xy,b_prime)) continue;
        float inv_depth = dot(b_prime,float3(p0.z,p1.z,p2.z));
        if (inv_depth <= 0) continue;
        uint depth_bits = asuint(1.0/inv_depth);
        uint index = uint(y)*width+uint(x);
        InterlockedMin(depth_buffer[index],depth_bits);
    }
}

[shader("compute")]
[numthreads(64, 1, 1)]
void rasterize_id(
        uint tid : SV_DispatchThreadID,
        uniform uint num_triangles,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        StructuredBuffer<float3> projected_vertices,
        RWStructuredBuffer<uint> depth_buffer,
        RWStructuredBuffer<uint> triangle_id_buffer) {
    if (tid >= num_triangles) return;
    uint3 face = faces[tid];
    float3 p0 = projected_vertices[face.x];
    float3 p1 = projected_vertices[face.y];
    float3 p2 = projected_vertices[face.z];
    if (min(p0.z,min(p1.z,p2.z)) <= 0) return;
    if (abs(edge_equation(p0.xy,p1.xy,p2.xy)) < 1e-8) return;
    int2 lo = max(int2(floor(min(p0.xy,min(p1.xy,p2.xy)))),int2(0));
    int2 hi = min(int2(ceil(max(p0.xy,max(p1.xy,p2.xy)))),int2(width-1,height-1));
    for (int y=lo.y; y<=hi.y; ++y) for (int x=lo.x; x<=hi.x; ++x) {
        float3 b_prime;
        if (!barycentric(float2(x,y)+0.5,p0.xy,p1.xy,p2.xy,b_prime)) continue;
        float inv_depth = dot(b_prime,float3(p0.z,p1.z,p2.z));
        if (inv_depth <= 0) continue;
        uint depth_bits = asuint(1.0/inv_depth);
        uint index = uint(y)*width+uint(x);
        if (depth_bits == depth_buffer[index]) InterlockedMin(triangle_id_buffer[index],tid);
    }
}

[shader("compute")]
[numthreads(8, 8, 1)]
void shade(
        uint2 tid : SV_DispatchThreadID,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        StructuredBuffer<float3> vertex_colors,
        StructuredBuffer<float3> projected_vertices,
        StructuredBuffer<uint> triangle_id_buffer,
        RWTexture2D<float4> image) {
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    uint face_id = triangle_id_buffer[tid.y*width+tid.x];
    if (face_id == 0xffffffff) return;
    uint3 face = faces[face_id];
    float3 p0 = projected_vertices[face.x], p1 = projected_vertices[face.y], p2 = projected_vertices[face.z];
    float3 b_prime;
    if (!barycentric(float2(tid)+0.5,p0.xy,p1.xy,p2.xy,b_prime)) return;
    float3 b = b_prime*float3(p0.z,p1.z,p2.z);
    b /= b.x+b.y+b.z;
    image[tid] = float4(b.x*vertex_colors[face.x]+b.y*vertex_colors[face.y]+b.z*vertex_colors[face.z],1.0);
}
