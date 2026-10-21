// Slang ports of kwandrus ToonShading.frag and Hatching.frag.
// Exact upstream files and attribution are in third_party/npr_glsl and THIRD_PARTY.md.
StructuredBuffer<float3> vertices;
StructuredBuffer<float3> vertex_normals;
StructuredBuffer<float2> vertex_uvs;
uniform float4x4 MVP;
uniform float4x4 model_matrix;
uniform float4x4 view_matrix;
uniform uint line_mode;
uniform float3x3 normal_matrix;
uniform float3 light_dir;
uniform float3 light_position;
uniform bool point_light;
uniform float3 light_color;
uniform float3 camera_position;
uniform float3 object_color;
uniform bool use_texture;
uniform float3 Ks;
uniform float exponent;
uniform uint style;
uniform float color_steps;
uniform float hatch_strength;
uniform float shadow_lift;
uniform float hatch_scale;
uniform float resolution_scale;
uniform uint render_height;
Texture2D<float4> Kd_texture;
SamplerState Kd_sampler;
Texture2D<float4> hatch0;
Texture2D<float4> hatch1;
Texture2D<float4> hatch2;
Texture2D<float4> hatch3;
Texture2D<float4> hatch4;
Texture2D<float4> hatch5;
struct VertexOutput {
    float4 position : SV_Position;
    float3 world_position : TEXCOORD0;
    float3 world_normal : TEXCOORD1;
    float2 uv : TEXCOORD2;
};
struct FragmentOutput {
    float4 color : SV_Target0;
    float4 normal_depth : SV_Target1;
};
[shader("vertex")]
VertexOutput vertex_main(uint vid : SV_VertexID) {
    VertexOutput output;
    output.position = mul(MVP,float4(vertices[vid],1.0));
    output.world_position = mul(model_matrix,float4(vertices[vid],1.0)).xyz;
    output.world_normal = mul(normal_matrix,vertex_normals[vid]);
    output.uv = vertex_uvs[vid];
    return output;
}
float hatch_tone(float diffuse, float2 pixel) {
    // The ORIGINAL maps gl_FragCoord to a repeating 256x256 texture, LOD 0.
    // Slang's top-left origin is flipped to OpenGL's bottom-left origin.
    // SSAA keeps the period at 256 OUTPUT pixels; scale=1 is the source period.
    float2 gl_pixel = float2(pixel.x,float(render_height)-pixel.y);
    int2 p = int2(gl_pixel/(resolution_scale*hatch_scale)) % 256;
    float lightIntensity = dot(float3(diffuse),float3(0.2326,0.7152,0.0722))*6.0;
    float3 w0 = saturate(lightIntensity-float3(0,1,2));
    float3 w1 = saturate(lightIntensity-float3(3,4,5));
    w0.xy -= w0.yz;
    w0.z -= w1.x;
    w1.xy -= w1.yz;
    return hatch5.Load(int3(p,0)).r*w0.x + hatch4.Load(int3(p,0)).r*w0.y
         + hatch3.Load(int3(p,0)).r*w0.z + hatch2.Load(int3(p,0)).r*w1.x
         + hatch1.Load(int3(p,0)).r*w1.y + hatch0.Load(int3(p,0)).r*w1.z;
}
[shader("fragment")]
FragmentOutput fragment_main(VertexOutput input) {
    float3 n = normalize(input.world_normal);
    float3 l = normalize(point_light ? light_position-input.world_position : light_dir);
    float3 v = normalize(camera_position-input.world_position);
    float3 texture_color = Kd_texture.Sample(Kd_sampler,input.uv).rgb;
    // Constant objectColor is linear in the upstream shader. Textured meshes
    // continue to use HW2's sRGB-decoded diffuse texture.
    float3 Kd = use_texture ? texture_color : object_color;
    float diffuse = max(dot(n,l),0.0);
    float specular = diffuse>0 ? pow(max(dot(reflect(-l,n),v),0.0),exponent) : 0;
    float toon = max(ceil(dot(n,l)*color_steps)/color_steps,0.0);
    float3 color = 0.2*Kd+Kd*light_color*diffuse+Ks*light_color*specular;
    if (style==1) color=Kd*light_color*toon; // original ToonShading.frag
    if (style==2) color=float3(0.94,0.92,0.87); // diagnostic: lines on paper
    if (style==3) color=float3(hatch_tone(diffuse,input.position.xy)); // original hatching
    if (style==4) {
        // Integration controls, not part of the original independent demos:
        // lift the darkest cel band so ink remains legible; then overlay hatching.
        color=Kd*light_color*lerp(shadow_lift,1.0,toon);
        color*=lerp(1.0,hatch_tone(lerp(shadow_lift,1.0,diffuse),input.position.xy),hatch_strength);
    }
    FragmentOutput output;
    output.color=float4(color,1.0);
    // Original Gooch MRT: interpolated world normal and world position.z.
    // Float targets retain signed values (see port differences in README_NPR).
    output.normal_depth=float4(input.world_normal,input.world_position.z);
    if(line_mode==1) {
        float3 view_normal=normalize(mul((float3x3)view_matrix,n));
        float view_depth=-mul(view_matrix,float4(input.world_position,1.0)).z;
        output.normal_depth=float4(view_normal,view_depth);
    }
    return output;
}
