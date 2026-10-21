// HW2 equations (4), (6), (11): coverage and inverse-depth weighting.
float edge_equation(float2 a, float2 b, float2 p)
{
    float2 e = b-a;
    return dot(p-a, float2(e.y, -e.x));
}
bool barycentric(float2 p, float2 a, float2 b, float2 c, out float3 weights)
{
    float area = edge_equation(a, b, c);
    weights = float3(0);
    if (abs(area) < 1e-8) return false;
    weights = float3(edge_equation(b,c,p), edge_equation(c,a,p), edge_equation(a,b,p)) / area;
    return all(weights >= 0.0);
}
