#version 310 es
precision highp float;
precision highp int;


layout(location = COLOR0) in vec4 v_color;
layout(location = TEXCOORD0) in vec2 v_texCoord;

layout(location = SV_Target0) out vec4 FragColor;

void main()
{
    float edgeDistance = length(v_texCoord);
    float aaWidth = max(fwidth(edgeDistance), 1.0 / 1024.0);
    float coverage = 1.0 - smoothstep(1.0 - aaWidth, 1.0, edgeDistance);
    FragColor = v_color * coverage;
}
