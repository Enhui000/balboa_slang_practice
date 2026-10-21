// Refined screen-space feature response. Operates on unit view normals and
// positive linear view depth; does not depend on object scale or world axes.
Texture2D<float4> normal_depth;
RWTexture2D<float4> features;
uniform uint width;
uniform uint height;
uniform uint ssaa;
uniform float camera_s;
float4 geometry(int2 p) {
    return normal_depth.Load(int3(clamp(p,int2(0),int2(width-1,height-1)),0));
}
float3 view_position(int2 p,float depth) {
    float2 ndc=(float2(p)+0.5)/float2(width,height)*2.0-1.0;
    return float3(ndc.x*camera_s*float(width)/float(height),-ndc.y*camera_s,-1)*depth;
}
[shader("compute")]
[numthreads(8,8,1)]
void compute_main(uint2 tid:SV_DispatchThreadID) {
    if(tid.x>=width || tid.y>=height) return;
    int2 p=int2(tid);
    float4 c=geometry(p);
    if(c.w<=0) { features[tid]=0; return; }
    float3 gx=0,gy=0;
    float occlusion=0;
    float3 position=view_position(p,c.w);
    float pixel_world=max(2.0*camera_s*c.w/float(height),1e-6);
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        if(x==0 && y==0) continue;
        int2 q=p+int2(x,y);
        float4 neighbor=geometry(q);
        // Do not blur foreground normals with the background/another layer.
        bool same_surface=neighbor.w>0 && abs(neighbor.w-c.w)<0.025*c.w;
        float3 n=same_surface ? neighbor.xyz : c.xyz;
        gx+=n*float(x)*(y==0?2.0:1.0)/8.0;
        gy+=n*float(y)*(x==0?2.0:1.0)/8.0;
        if(neighbor.w>c.w) {
            float3 delta=view_position(q,neighbor.w)-position;
            // Tangent-plane residual rejects steep but continuous surfaces.
            // Draw an occlusion on its nearer side only, avoiding double edges.
            float plane_error=abs(dot(c.xyz,delta))/pixel_world;
            float gap=(neighbor.w-c.w)/pixel_world;
            occlusion=max(occlusion,smoothstep(1.0,2.5,plane_error)*smoothstep(1.5,3.0,gap));
        }
    }
    // Dominant direction of change for a vector-valued normal field.
    float A=dot(gx,gx),B=dot(gx,gy),C=dot(gy,gy);
    float theta=0.5*atan2(2.0*B,A-C+1e-12);
    float2 direction=float2(cos(theta),sin(theta));
    float magnitude=sqrt(max(0.0,0.5*(A+C+sqrt((A-C)*(A-C)+4.0*B*B))))*float(ssaa);
    // Preserve the unsaturated response for thinning; clipping before this
    // step would turn detailed regions into broad plateaus of ink.
    features[tid]=float4(magnitude,occlusion,direction);
}
