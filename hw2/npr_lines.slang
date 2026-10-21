// Port of kwandrus/SobelOutline.frag; upstream calls this a Sobel filter,
// though its actual operator is a weighted center-difference range.
// Same normal/depth operator, weights, threshold squaring and max composition.
Texture2D<float4> scene_color;
Texture2D<float4> normal_depth;
RWTexture2D<float4> output_image;
uniform uint width;
uniform uint height;
uniform uint style;
uniform uint ssaa;
uniform float line_width;
uniform float normal_threshold;
uniform float depth_threshold;
uniform float line_opacity;
uniform float3 ink_color;
float4 geometry(int2 p) {
    // Defined behavior at viewport borders, unlike out-of-range texelFetch.
    return normal_depth.Load(int3(clamp(p,int2(0),int2(width-1,height-1)),0));
}
float edge_at(int2 p) {
    float4 center=geometry(p);
    float depth_range=0;
    float normal_range=0;
    int radius=max(1,int(round(line_width*float(ssaa))));
    for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
        if (x==0 && y==0) continue;
        float weight=(x==0 || y==0) ? 2.0/8.0 : 1.0/8.0;
        float4 sample=geometry(p+int2(x,y)*radius);
        depth_range=max(depth_range,abs(sample.w-center.w)*weight);
        normal_range=max(normal_range,length(sample.xyz-center.xyz)*weight);
    }
    // The center's filter weight is zero, so upstream gmin is always zero.
    float d=depth_range/depth_threshold;
    float n=normal_range/normal_threshold;
    return saturate(max(d*d,n*n));
}
[shader("compute")]
[numthreads(8,8,1)]
void compute_main(uint2 tid : SV_DispatchThreadID) {
    uint out_width,out_height;
    output_image.GetDimensions(out_width,out_height);
    if (tid.x>=out_width || tid.y>=out_height) return;
    float3 total=0;
    for (uint y=0;y<ssaa;y++) for (uint x=0;x<ssaa;x++) {
        int2 p=int2(tid*ssaa+uint2(x,y));
        float3 color=scene_color.Load(int3(p,0)).rgb;
        if (style==2 || style==4) color=lerp(color,ink_color,edge_at(p)*line_opacity);
        total+=color;
    }
    output_image[tid]=float4(total/float(ssaa*ssaa),1.0);
}
