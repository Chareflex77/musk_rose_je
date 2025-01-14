#if !defined LIGHTING_INCLUDED
#define LIGHTING_INCLUDED 1

#if defined FORWARD_FRAGMENT
uniform mat4 gbufferModelView, gbufferModelViewInverse;
uniform mat4 gbufferProjection, gbufferProjectionInverse;
uniform mat4 shadowProjection, shadowModelView;
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D gaux1;
uniform sampler2D gaux3;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D specular;
uniform vec3 cameraPosition;
uniform vec3 fogColor;
uniform float rainStrength;
uniform float frameTimeCounter;
uniform float far, near;
uniform float aspectRatio;
uniform int moonPhase;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;

varying vec2 uv;
varying vec3 sunPos, moonPos, shadowLightPos;

#include "/utilities/muskRoseWater.glsl"

vec4 getViewPos(const mat4 projInv, const vec2 uv, const float depth) {
	vec4 viewPos = projInv * vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);

	return viewPos / viewPos.w;
}

vec4 getRelPos(const mat4 modelViewInv, const mat4 projInv, const vec2 uv, const float depth) {
	vec4 relPos = modelViewInv * getViewPos(projInv, uv, depth);
	
	return relPos / relPos.w;
}

#include "/utilities/muskRoseShadow.glsl"

#define SHADOW_BIAS 0.03 // [0.00 0.01 0.02 0.03 0.04 0.05]

vec4 getShadowPos(const mat4 modelViewInv, const mat4 projInv, const mat4 shadowModelView, const mat4 shadowProj, const vec3 relPos, const vec2 uv, const float depth, const float diffuse) {
	vec4 shadowPos = vec4(relPos, 1.0);
	shadowPos = shadowProj * (shadowModelView * shadowPos);
	
	float distortFactor = getDistortFactor(shadowPos.xy);
	shadowPos.xyz = distort(shadowPos.xyz);
	shadowPos.xyz = shadowPos.xyz * 0.5 + 0.5;
	
	shadowPos.z -= SHADOW_BIAS * (distortFactor * distortFactor) / abs(diffuse);

	return shadowPos;
}

#define ENABLE_SPECULAR

float getSpecularLight(const float fresnel, const float shininess, const vec3 lightDir, const vec3 relPos, const vec3 normal) {
    vec3  viewDir   = -normalize(relPos);
    vec3  halfDir   = normalize(viewDir + lightDir);
    float incident  = 1.0 - max(0.0, dot(lightDir, halfDir));
    incident = incident * incident * incident * incident * incident;
    float refAngle  = max(0.0, dot(halfDir, normal));
    float diffuse   = max(0.0, dot(normal, lightDir));
    float reflCoeff = fresnel + (1.0 - fresnel) * incident;
    float specular  = pow(refAngle, shininess) * reflCoeff * diffuse;

    float viewAngle = 1.0 - max(0.0, dot(normal, viewDir));
    viewAngle = viewAngle * viewAngle * viewAngle * viewAngle;
    float viewCoeff = fresnel + (1.0 - fresnel) * viewAngle;

#   if defined ENABLE_SPECULAR
        return max(0.0, specular * viewCoeff * 0.03);
#   else
        return 0.0;
#   endif
}

vec3 hdrExposure(const vec3 col, const float overExposure, const float underExposure) {
    vec3 overExposed   = col / overExposure;
    vec3 normalExposed = col;
    vec3 underExposed  = col * underExposure;

    return mix(overExposed, underExposed, normalExposed);
}

/*
 ** Uncharted 2 tone mapping
 ** Link (deleted): http://filmicworlds.com/blog/filmic-tonemapping-operators/
 ** Archive: https://bit.ly/3NSGy4r
 */
vec3 uncharted2ToneMap_(vec3 x) {
    const float A = 0.015; // Shoulder strength
    const float B = 0.500; // Linear strength
    const float C = 0.100; // Linear angle
    const float D = 0.010; // Toe strength
    const float E = 0.020; // Toe numerator
    const float F = 0.300; // Toe denominator

    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}
vec3 uncharted2ToneMap(const vec3 col, const float exposureBias) {
    const float whiteLevel = 256.0;

    vec3 curr = uncharted2ToneMap_(exposureBias * col);
    vec3 whiteScale = 1.0 / uncharted2ToneMap_(vec3(whiteLevel, whiteLevel, whiteLevel));
    vec3 color = curr * whiteScale;

    return clamp(color, 0.0, 1.0);
}

vec3 contrastFilter(const vec3 col, const float contrast) {
    return (col - 0.5) * max(contrast, 0.0) + 0.5;
}

#include "/utilities/muskRoseSky.glsl"
#include "/utilities/muskRoseSSAO.glsl"

#if !defined WORLD1
#   define SKY_COL  vec3(0.4, 0.65, 1.0)
#else
#   define SKY_COL  vec3(0.6, 0.8, 1.0)
#endif

#define RAY_COL  vec3(0.63, 0.62, 0.45)

#define AMBIENT_LIGHT_INTENSITY 10.0
#if !defined WORLDM1
#   define SKYLIGHT_INTENSITY 30.0
#else
#   define SKYLIGHT_INTENSITY 160.0
#endif
#define SUNLIGHT_INTENSITY 30.0
#define MOONLIGHT_INTENSITY 10.0
#define TORCHLIGHT_INTENSITY 60.0

#define SKYLIGHT_COL vec3(0.9, 0.98, 1.0)
#define SUNLIGHT_COL vec3(1.0, 0.9, 0.85)
#define SUNLIGHT_COL_SET vec3(1.0, 0.70, 0.1)
#define TORCHLIGHT_COL vec3(1.0, 0.65, 0.3)
#define MOONLIGHT_COL vec3(0.2, 0.4, 1.0)

#define EXPOSURE_BIAS 5.0
#define GAMMA 2.3 // [1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8]

const float sunPathRotation = -40.0; // [-50  -45 -40  -35 -30 -25 -20 -15 -10 -5 0 5 10 15 20 25 30 35 40 45 50]
const int shadowMapResolution = 2048; // [512 1024 2048 4096]
const float shadowDistance = 512.0;
#define VANNILA_AO_INTENSITY 1.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define SHADER_AO_INTENSITY 0.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]
#define OCCL_SHADOW_BRIGHTNESS 0.2 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

#define ENABLE_SUNRAYS
#define ENABLE_UNDERWATER_RAYS
// #define ENABLE_COLED_RAYS
#define ENABLE_FOG

void main() {
vec3 albedo = texture2D(gcolor, uv).rgb;
#if defined FORWARD_DEFERRED
    vec3 backward = albedo;
#endif
vec3 bloom = texture2D(colortex9, uv).rgb;
vec3 normal = texture2D(gnormal, uv).rgb * 2.0 - 1.0;
vec2 uv1 = texture2D(gaux1, uv).rg;
float blendFlag = texture2D(gaux1, uv).b;
float waterFlag = texture2D(gaux3, uv).r;
float blendAlpha = texture2D(gaux3, uv).g;
float depth = texture2D(depthtex0, uv).r;
vec3 viewPos = getViewPos(gbufferProjectionInverse, uv, depth).xyz;
vec3 relPos  = getRelPos(gbufferModelViewInverse, gbufferProjectionInverse, uv, depth).xyz;
vec3 fragPos = relPos + cameraPosition;
vec3 skyPos = normalize(relPos);
float diffuse = max(0.0, dot(shadowLightPos, normal));
float daylight = 
#if !defined WORLDM1
    max(0.0, sin(sunPos.y));
#else
    1.0;
#endif
float duskDawn = min(smoothstep(0.0, 0.3, daylight), smoothstep(0.5, 0.3, daylight));
float amnientLightFactor = 1.0;
float dirLightFactor = 0.0;
float emissiveLightFactor = 0.0;
float clearWeather = 
#if defined WORLD0
    1.0 - rainStrength;
#else
    1.0;
#endif
vec3 sky = 
#if !defined WORLDM1
    getSky(skyPos, shadowLightPos, moonPos, SKY_COL, daylight, 1.0 - clearWeather, frameTimeCounter, moonPhase);
#else
    fogColor;
#endif
vec3 skylightCol = vec3(0.0);
vec3 sunlightCol = mix(SUNLIGHT_COL, SUNLIGHT_COL_SET, duskDawn);
vec3 daylightCol = mix(sky, sunlightCol, 0.4);
vec3 ambientLightCol = vec3(1.0);
vec4 shadows = vec4(vec3(diffuse), 1.0);
float vanillaAO = texture2D(gaux3, uv).b * VANNILA_AO_INTENSITY;
float shaderAO = getSSAO(viewPos, gbufferProjectionInverse, uv, aspectRatio, depthtex0) * SHADER_AO_INTENSITY;
float totalAO =
#ifdef ENABLE_AO
    clamp(vanillaAO + shaderAO, 0.0, 1.0);
#else
    0.0;
#endif
float occlShadow = mix(1.0, OCCL_SHADOW_BRIGHTNESS, totalAO);
float fresnel = texture2D(colortex8, uv).r * 100.0;
float shininess = texture2D(colortex8, uv).r * 500.0;

vec3 light = vec3(0.0);

#if defined FORWARD_DEFERRED
    if (depth == 1.0) {
        albedo = sky;
        float sunTrim =
#   	if !defined WORLD1
            smoothstep(0.1, 0.0, distance(skyPos, sunPos));
#   	else
            1.0;
        #endif
        bloom += getSun(cross(skyPos, sunPos) * 25.0) * smoothstep(0.0, 0.01, daylight) * sunTrim;
    } else
#elif defined FORWARD_COMPOSITE
    if (blendFlag > 0.5)
#endif
{
    vec4 shadowPos = getShadowPos(gbufferModelViewInverse, gbufferProjectionInverse, shadowModelView, shadowProjection, relPos, uv, depth, diffuse);
    if (diffuse > 0.0 && shadowPos.w > 0.0) {
        vec2 offset = vec2(0.0);
        offset += hash12(floor(uv * 2048.0)) * 0.00025;
        if (texture2D(shadowtex0, shadowPos.xy + offset).r < shadowPos.z) {
            if (texture2D(shadowtex1, shadowPos.xy + offset).r < shadowPos.z) {
                shadows = vec4(vec3(0.0), 0.0);
            } else {
                shadows = vec4(texture2D(shadowcolor0, shadowPos.xy + offset).rgb, 0.0);
            }
        }
    }
    
    shadows = mix(vec4(vec3(0.0), 0.0), shadows, smoothstep(0.0, 0.1, uv1.y));

    amnientLightFactor = 
#   if !defined WORLD1
        mix(0.0, mix(0.2, 1.4, daylight), uv1.y);
#   else
        mix(0.2, mix(0.2, 1.4, daylight), uv1.y);
#   endif

    dirLightFactor = 
#   if !defined WORLDM1
        mix(0.0, diffuse, shadows.a);
#   else
        0.5;
#   endif
    emissiveLightFactor = uv1.x * uv1.x * uv1.x * uv1.x * uv1.x;
    ambientLightCol = mix(mix(vec3(0.0), TORCHLIGHT_COL, emissiveLightFactor), mix(MOONLIGHT_COL, daylightCol, daylight), dirLightFactor);
    ambientLightCol += 1.0 - max(max(ambientLightCol.r, ambientLightCol.g), ambientLightCol.b);
    skylightCol = 
#   if !defined WORLDM1
        getSkyLight(reflect(skyPos, normal), shadowLightPos, SKY_COL, daylight, 1.0 - clearWeather);
#   else
        fogColor;
#   endif

    if (blendFlag > 0.5) {
        fresnel   = 100.0;
        shininess = 500.0;
    }
    float specularLight = getSpecularLight(fresnel, shininess, shadowLightPos, relPos, normal);

    light += ambientLightCol * AMBIENT_LIGHT_INTENSITY * amnientLightFactor * occlShadow;
#   if !defined WORLDM1
        light += sunlightCol * SUNLIGHT_INTENSITY * dirLightFactor * daylight * clearWeather * blendAlpha;
        light += MOONLIGHT_COL * MOONLIGHT_INTENSITY * dirLightFactor * (1.0 - daylight) * clearWeather;
#   endif
        light += skylightCol * SKYLIGHT_INTENSITY * dirLightFactor * daylight * clearWeather * blendAlpha;
        light += TORCHLIGHT_COL * TORCHLIGHT_INTENSITY * emissiveLightFactor * blendAlpha;

    /*
    ** Apply coloured shadows.
    */
    vec3 lightCol = (normalize(light) + 1.0) * 0.5;
    vec3 lightColBright = lightCol + 1.0 - max(lightCol.r, max(lightCol.g, lightCol.b));
    light += (lightColBright - (1.0 - shadows.rgb)) * (1.0 - shadows.a * diffuse) * light * (waterFlag > 0.5 ? blendAlpha : 1.0);

#   if !defined WORLDM1
        vec3 totalSpecular = light * specularLight * dirLightFactor * daylight * clearWeather;
        light += totalSpecular;
        bloom += totalSpecular;
#   endif

    albedo = pow(albedo, vec3(GAMMA));
    albedo *= light;
    albedo = hdrExposure(albedo, EXPOSURE_BIAS, 0.2);
    albedo = uncharted2ToneMap(albedo, EXPOSURE_BIAS);
    albedo = pow(albedo, vec3(1.0 / GAMMA));
    albedo = contrastFilter(albedo, GAMMA - 0.6);

    float fogDistanceMult =
#       if defined WORLD1
            3.0;
#       else
            1.0 * mix(1.0, 4.0, 1.0 - clearWeather);
#       endif
    float fogFactor = 
    #ifdef ENABLE_FOG
        clamp((length(relPos * fogDistanceMult) - near) / (far - near), 0.0, 1.0);
    #else
        0.0;
    #endif
    float fogBrightness =
#   if !defined WORLD1
        mix(0.7, 2.0, smoothstep(0.0, 0.1, daylight) * float(eyeBrightnessSmooth.y / 240.0));
#   else
        2.0;
#   endif
    vec3 fogCol = 
#   if !defined WORLDM1
        toneMapReinhard(getAtmosphere(skyPos, shadowLightPos, SKY_COL, fogBrightness));
#   else
        fogColor;
#   endif
    albedo = mix(albedo, mix(fogCol, vec3(dot(fogCol, vec3(0.22, 0.707, 0.071))), 1.0 - clearWeather), fogFactor);
}

#if defined FORWARD_DEFERRED
    if (
    #ifdef ENABLE_COLED_RAYS
        true
    #else
        depth != 1.0
    #endif
    )
#elif defined FORWARD_COMPOSITE
    if (blendFlag > 0.5)
#endif
{
    float rayFactor = 0.0;
    vec3 rayShadowCol = vec3(0.0);
    vec3 totalrayCol = RAY_COL;
    vec3 relPosRay = relPos;
    relPosRay.xyz *= mix(1.0, 1.3, hash12(floor(gl_FragCoord.xy * 2048.0) + frameTimeCounter));
    while (dot(relPosRay.xyz, relPosRay.xyz) > 0.25 * 0.25) {
        relPosRay.xyz *= 0.75;
        vec4 rayPos = getShadowPos(gbufferModelViewInverse, gbufferProjectionInverse, shadowModelView, shadowProjection, relPosRay, uv, depth, 1.0);
        if (texture2D(shadowtex1, rayPos.xy).r > rayPos.z) {
            if (depth != 1.0) {
                rayFactor = mix(rayPos.w, rayFactor, exp2(length(relPosRay.xyz) * -0.0625));
            }
            #ifdef ENABLE_COLED_RAYS
                if (texture2D(shadowtex0, rayPos.xy).r < rayPos.z) {
                    if (depth == 1.0) {
                        rayFactor = mix(rayPos.w, rayFactor, exp2(length(relPosRay.xyz) * -0.0625));
                    }
                    rayShadowCol = texture2D(shadowcolor0, rayPos.xy).rgb;
                    rayShadowCol = rayShadowCol + 1.0 - max(rayShadowCol.r, max(rayShadowCol.g, rayShadowCol.b));
                    vec3 rayColBright = totalrayCol + 1.0 - max(totalrayCol.r, max(totalrayCol.g, totalrayCol.b));
                    float rayBrightness = dot(totalrayCol, vec3(0.4));
                    totalrayCol = clamp(mix(rayColBright, rayShadowCol, blendAlpha * rayBrightness) * rayBrightness, 0.0, 1.0);
                }
            #endif
        }
    }
    float sunRayFactor = 
    #ifdef ENABLE_SUNRAYS
        isEyeInWater == 0 ? min(rayFactor * max(0.0, 1.0 - distance(skyPos, sunPos)) * smoothstep(0.0, 0.1, daylight), 1.0) : 0.0;
    #else
        0.0;
    #endif

#   if !defined WORLDM1
        albedo = mix(albedo, totalrayCol, sunRayFactor);
#   endif
}

#if defined FORWARD_DEFERRED
    backward = albedo;
#endif

    /* DRAWBUFFERS:059
     * 0 = gcolor
     * 1 = gdepth
     * 2 = gnormal
     * 3 = composite
     * 4 = gaux1
     * 5 = gaux2
     * 6 = gaux3
     * 7 = gaux4
    */
	gl_FragData[0] = vec4(albedo, 1.0); // gcolor
#   if defined FORWARD_DEFERRED
    gl_FragData[1] = vec4(backward, 1.0); // gaux2
#   endif
    gl_FragData[2] = vec4(bloom, 1.0); // colortex9
}
#endif /* defined FORWARD_FRAGMENT */

#if defined FORWARD_VERTEX
uniform mat4 gbufferModelView, gbufferModelViewInverse;
uniform vec3 sunPosition, moonPosition, shadowLightPosition;

varying vec2 uv;
varying vec3 sunPos, moonPos, shadowLightPos;

void main() {
uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
#if !defined WORLD1
    sunPos         = normalize(mat3(gbufferModelViewInverse) * mat3(gl_ModelViewMatrix) * sunPosition);
    moonPos        = normalize(mat3(gbufferModelViewInverse) * mat3(gl_ModelViewMatrix) * moonPosition);
    shadowLightPos = normalize(mat3(gbufferModelViewInverse) * mat3(gl_ModelViewMatrix) * shadowLightPosition);
#else
    sunPos         = vec3(0.0, 1.0, 1.0);
    moonPos        = -sunPos;
    shadowLightPos = vec3(0.0, 1.0, 1.0);
#endif

	gl_Position = ftransform();
}
#endif /* defined FORWARD_VERTEX */
#endif /* !defined LIGHTING_INCLUDED */