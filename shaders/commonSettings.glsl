#define OFF 0
#define ON 1
// Shadow settings
#define ENABLE_SHADOWS OFF // Enable shadow mapping [OFF ON]
#define COLORED_SHADOWS ON // Enable colored shadows [OFF ON]
#define SHADOW_BRIGHTNESS 0.60 //Light levels are multiplied by this number when the surface is in shadows [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define BLOCK_LIGHT_INTENSITY 0.8 // Controls brightness of block lights (torches, lanterns, etc) [0.0 0.25 0.5 0.75 0.8 0.85 1.0 1.25 1.5 2.0]

//texture settings - Updated to use style system:
#define Shininess 0.0 //Water shine intensity [0.0 0.25 0.5 0.75 1.0]
#define ENABLE_DIRECTIONAL_LIGHTING 1 // Enable directional lighitng [OFF ON]
#define ENABLE_VORONOI_DISTORTION 0 // Enable voronoi distortion [OFF ON]

// Soft shadow settings
#define SOFT_SHADOWS ON // Enable soft shadows [OFF ON]
#define PCF_SAMPLE 16 //[8 16 32 64]
#define PCF_BLUR_RADIUS 2.0 //[1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0]

const int shadowMapResolution = 1024; //[512 1024 2048 4096 8192]
const int noiseTextureResolution = 256;
const float shadowDistance = 256.0; //[64.0 96.0 128.0 160.0 192.0 224.0 256.0 288.0 320.0 352.0 384.0 416.0 448.0 480.0 512.0]

#define SHADOW_DISTORTION ON // Enable shadow map distortion [0 1]
#define SHADOW_DISTORT_REDUCTION 0.15 // Distortion Reduction [0.05 0.10 0.15 0.20 0.25 0.30]
#define FAR_DISTANCE_BIAS_START 16.0 // Distance where extra bias scaling starts [16.0 24.0 32.0 40.0 48.0 56.0 64.0]
#define FAR_DISTANCE_BIAS_RANGE 48.0 // Range over which bias scales [32.0 48.0 64.0 80.0 96.0 112.0 128.0]
#define FAR_DISTANCE_BIAS_MAX 4.0 // Maximum bias multiplier for far distances [2.0 3.0 4.0 5.0]

#define HALF_LAMBERT 0
#define LAMBERT 1
#define LAMBERT_MODE HALF_LAMBERT //[HALF_LAMBERT LAMBERT]

#define CEL OFF //[OFF ON]

vec3 distortShadow(vec3 pos) {
    #if SHADOW_DISTORTION == 1
        float factor = length(pos.xy) + SHADOW_DISTORT_REDUCTION;
        return vec3(pos.xy / factor, pos.z * 0.5);
    #else
        return pos;
    #endif
}