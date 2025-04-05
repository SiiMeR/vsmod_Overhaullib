#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outGlow;
#if SSAOLEVEL > 0
in vec4 gnormal;
layout(location = 2) out vec4 outGNormal;
layout(location = 3) out vec4 outGPosition;
#endif

uniform sampler2D tex;
uniform float extraGodray = 0;
uniform float alphaTest = 0.001;
uniform float ssaoAttn = 0;
uniform int applySsao = 1;

// Texture overlay "hack"
// We only have the base texture UV coordinates, which, for blocks and items in inventory is the block or item texture atlas, but none uv coords for a dedicated overlay texture
// So lets remove the base offset (baseUvOrigin) and rescale the coords (baseTextureSize / overlayTextureSize) to get useful UV coordinates for the overlay texture
uniform sampler2D tex2dOverlay;
uniform float overlayOpacity;
uniform vec2 overlayTextureSize;
uniform vec2 baseTextureSize;
uniform vec2 baseUvOrigin;
uniform int normalShaded;
uniform float damageEffect = 0;
#if defined(ALLOWDEPTHOFFSET) && ALLOWDEPTHOFFSET > 0
uniform float depthOffset;
#endif

in vec2 uv;
in vec4 color;
in vec4 rgbaFog;
in float fogAmount;
in float glowLevel;
in vec4 rgbaGlow;
in vec4 camPos;
in vec4 worldPos;
in vec3 normal;
flat in int renderFlags;


#include fogandlight.fsh
#include noise2d.ash

void main() {
	float b = 1;
	
	if (damageEffect > 0) {
		float f = cnoise2(floor(vec2(uv.x, uv.y) * 4096) / 4);
		if (f < damageEffect - 1.3) discard;
		b = min(1, f * 1.5 + 0.65 + (1-damageEffect));
	}

	if (overlayOpacity > 0) {
		vec2 uvOverlay = (uv - baseUvOrigin) * (baseTextureSize / overlayTextureSize);

		vec4 col1 = texture(tex2dOverlay, uvOverlay);
		vec4 col2 = texture(tex, uv);

		float a1 = overlayOpacity * col1.a  * min(1, col2.a * 100);
		float a2 = col2.a * (1 - a1);

		outColor = vec4(
		  (a1 * col1.r + col2.r * a2) / (a1+a2),
		  (a1 * col1.b + col2.g * a2) / (a1+a2),
		  (a1 * col1.g + col2.b * a2) / (a1+a2),
		  a1 + a2
		) * color;

	} else {
		outColor = texture(tex, uv) * color;
	}

#if BLOOM == 0
	outColor.rgb *= 1 + glowLevel;
#endif

	if (normalShaded > 0) {
		float b = min(1, getBrightnessFromNormal(normal, 1, 0.45) + glowLevel);
		outColor *= vec4(b, b, b, 1);
	}
		
	outColor = applyFogAndShadow(outColor, fogAmount);
	
#if NORMALVIEW == 0
	if (outColor.a < alphaTest) discard;
#endif
	
	float glow = 0;
#if SHINYEFFECT > 0	
	outColor = mix(applyReflectiveEffect(outColor, glow, renderFlags, uv, normal, worldPos, camPos, vec3(1)), outColor, min(1, 2 * fogAmount));
	glow = pow(max(0, dot(normal, lightPosition)), 6) / 8 * shadowIntensity * (1 - fogAmount);
#endif

#if SSAOLEVEL > 0
	if (applySsao > 0) {
		outGPosition = vec4(camPos.xyz, fogAmount + glowLevel);
	} else {
		outGPosition = vec4(camPos.xyz, 1);
	}
	outGNormal = vec4(gnormal.xyz, ssaoAttn);
	
#endif

#if NORMALVIEW > 0
	outColor = vec4((normal.x + 1) / 2, (normal.y + 1)/2, (normal.z+1)/2, 1);	
#endif

	outColor.rgb *= b;
	outGlow = vec4(glowLevel + glow, extraGodray - fogAmount, 0, outColor.a);

#if defined(ALLOWDEPTHOFFSET) && ALLOWDEPTHOFFSET > 0
	// This likely tanks performance in any other scenario so we do only only for the first person mode rendering. See also https://www.khronos.org/opengl/wiki/Early_Fragment_Test#Limitations
	gl_FragDepth = gl_FragCoord.z + depthOffset;

	// A bit hacky: We use ALLOWDEPTHOFFSET for the first person rendering. SSAO seems to break on it, so we disable it
	#if SSAOLEVEL > 0
		outGPosition.w=1;
	#endif
#endif
}
