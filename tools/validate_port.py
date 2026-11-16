# -*- coding: utf-8 -*-
"""
Offline self-test for the Outline Shader NE port.

It does not run Minecraft.  It stubs the NetEase ModSDK client modules, imports
the real script + shader metadata, and checks that:

    * every original option is present and in range,
    * the original final.fsh outline algorithm is still in the fragment shader,
    * the settings page registers all controls,
    * slider / toggle / dropdown callbacks reach SetParameter correctly,
    * values are persisted and restored through the config component,
    * the two post-process descriptions are valid JSON.

Run with any Python 2.7/3.x:
    python ne_be/tools/validate_port.py
"""

from __future__ import print_function

import json
import io
import os
import sys
import types

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT_DIR = os.path.join(ROOT, "addon", "OutlineShaderNE_Beh")
RES_DIR = os.path.join(ROOT, "addon", "OutlineShaderNE_Res")
sys.path.insert(0, SCRIPT_DIR)

FRAGMENT = os.path.join(RES_DIR, "shaders", "glsl", "outline_shader_ne.fragment")
SHADOW_FRAGMENT = os.path.join(RES_DIR, "shaders", "glsl", "shadow_shader_ne.fragment")
MATERIAL = os.path.join(RES_DIR, "materials", "postprocess.material")

FAILURES = []


def check(condition, message):
    if condition:
        print("  ok   " + message)
    else:
        print("  FAIL " + message)
        FAILURES.append(message)


# ---------------------------------------------------------------------------
# ModSDK stubs
# ---------------------------------------------------------------------------
class BaseSystem(object):
    def __init__(self, namespace, system_name):
        self._listeners = []

    def ListenForEvent(self, namespace, system_name, event_name, target, callback):
        self._listeners.append((event_name, callback))


class FakeConfigComp(object):
    def __init__(self):
        self.store = {}

    def GetConfigData(self, name, is_global=False):
        return dict(self.store.get((name, bool(is_global)), {}))

    def SetConfigData(self, name, value, is_global=False):
        self.store[(name, bool(is_global))] = dict(value)
        return True


class FakePostComp(object):
    def __init__(self):
        self.order = []
        self.processes = {}
        self.enabled = {}
        self.params = {}

    def GetPostProcessOrder(self):
        return list(self.order)

    def AddPostProcess(self, process, index=-1):
        name = process["name"]
        if name in self.processes:
            return False
        self.processes[name] = process
        if index is None or index < 0 or index >= len(self.order):
            self.order.append(name)
        else:
            self.order.insert(index, name)
        self.enabled[name] = bool(process.get("enable", False))
        return True

    def SetParameter(self, post_name, param_name, value):
        if post_name not in self.processes:
            return False
        self.params[(post_name, param_name)] = list(value)
        return True

    def SetEnableByName(self, name, enable):
        if name not in self.processes:
            return False
        self.enabled[name] = bool(enable)
        return True


class FakeSettingInst(object):
    def __init__(self):
        self.controls = []

    def Clear(self):
        self.controls = []
        return self

    def AddText(self, key, name, priority=None):
        self.controls.append(("text", key, name, priority))
        return self

    def AddToggle(self, key, name, callback, priority=None, default=False):
        self.controls.append(("toggle", key, name, priority, bool(default), callback))
        return self

    def AddSlider(self, key, name, step, callback, priority=None, default=0):
        self.controls.append(("slider", key, name, priority, int(default), callback, int(step)))
        return self

    def AddDropDown(self, key, name, options, callback, priority=None, default=None):
        self.controls.append(("dropdown", key, name, priority, default, callback, list(options)))
        return self


class FakeWindowComp(object):
    def __init__(self):
        self.instances = {}

    def RegisterSettingInst(self, namespace, name, icon):
        if namespace not in self.instances:
            self.instances[namespace] = FakeSettingInst()
        return self.instances[namespace]


class FakeFactory(object):
    def __init__(self):
        self.config = FakeConfigComp()
        self.post = FakePostComp()
        self.window = FakeWindowComp()

    def CreateConfigClient(self, level_id):
        return self.config

    def CreatePostProcess(self, level_id):
        return self.post

    def CreateNeteaseWindow(self, level_id):
        return self.window


FACTORY = FakeFactory()

client_api = types.ModuleType("mod.client.extraClientApi")
client_api.GetClientSystemCls = lambda: BaseSystem
client_api.GetEngineNamespace = lambda: "minecraft"
client_api.GetEngineSystemName = lambda: "engine"
client_api.GetLevelId = lambda: "level"
client_api.GetEngineCompFactory = lambda: FACTORY

mod_mod = types.ModuleType("mod.common.mod")


class _Mod(object):
    @staticmethod
    def Binding(name=None, version=None):
        def deco(cls):
            cls._bound_name = name
            return cls
        return deco

    @staticmethod
    def InitClient():
        return lambda func: func

    @staticmethod
    def DestroyClient():
        return lambda func: func


mod_mod.Mod = _Mod

mod_pkg = types.ModuleType("mod")
mod_pkg.__path__ = []
client_pkg = types.ModuleType("mod.client")
client_pkg.__path__ = []
client_pkg.extraClientApi = client_api
common_pkg = types.ModuleType("mod.common")
common_pkg.__path__ = []
common_pkg.mod = mod_mod

sys.modules["mod"] = mod_pkg
sys.modules["mod.client"] = client_pkg
sys.modules["mod.client.extraClientApi"] = client_api
sys.modules["mod.common"] = common_pkg
sys.modules["mod.common.mod"] = mod_mod

from OutlineShaderScript import ShaderSettings as S  # noqa: E402
from OutlineShaderScript import OutlineShaderNEClient as C  # noqa: E402


# ---------------------------------------------------------------------------
# 1. shader source checks
# ---------------------------------------------------------------------------
print("1. fragment shader keeps the original outline algorithm")
frag = io.open(FRAGMENT, "r", encoding="utf-8").read()
original_lines = [
    "float getRimIntensity(float depthOft1,float depthOft2,float depth)",
    "float depthDiffer1 = (depthOft1 - depth) * OUTLINE_MODE;",
    "float depthDiffer2 = (depthOft2 - depth) * OUTLINE_MODE;",
    "float rimIntensity1 = step(THRESHOLD,depthDiffer1);",
    "float rimIntensity2 = step(THRESHOLD,depthDiffer2);",
    "float rimIntensity = max(rimIntensity1,rimIntensity2);",
    "float rampValue = 0.0001;",
    "rampValue = 0.001;",
    "float isRamp = step(rampValue,abs(depthDiffer1+depthDiffer2));",
    "return min(rimIntensity,isRamp);",
    "depth = depth * 2.0 - 1.0;",
    "return projInv[3].z / (projInv[2].w * depth + projInv[3].w);",
    "float linearDepth = max(-viewDepth, 0.0);",
    "linearDepth = 1.0 - linearDepth;",
    "(RIM_OFFECT / viewWidth) * SCREEN_VALUE",
    "vec4 outlineCol = vec4(OUTLINE_COL,OUTLINE_COL,OUTLINE_COL,1);",
    "finalColor.rgb = mix(finalColor.rgb, vec3(0.05, 0.05, 0.05), outline);",
    "return clamp(maxDiff * 4.0, 0.0, 1.0);",
]
for line in original_lines:
    check(line in frag, "verbatim: " + line[:64])
check("#define a " not in frag, "no single-letter macro 'a' (would corrupt .a swizzles)")
check("#define texcoord uv" in frag, "texcoord alias keeps the original variable names")
check("gbufferProjectionInverse = inverse(PROJ);" in frag, "projection inverse filled once")
check("texture2D(TEXTURE_2" in frag, "depth taps read TEXTURE_2")
check("TEXTURE_3" in frag, "cel ramp bound as TEXTURE_3")
check("float sampleCelRamp(float luma)" in frag, "cel ramp has a procedural fallback")
check("precision highp float;" in frag, "fragment precision declared (as in vanilla post-process shaders)")
check("FAR_CHUNKS_DISTANCE" in frag, "far plane taken from the engine depth far distance")

shadow = io.open(SHADOW_FRAGMENT, "r", encoding="utf-8").read()
check("EXTRA_VECTOR1" in shadow and "EXTRA_VECTOR2" in shadow,
      "shadow pass receives all shadow parameters")
check("inverse(PROJ)" in shadow, "shadow pass reconstructs view depth")

# ---------------------------------------------------------------------------
# 2. option tables
# ---------------------------------------------------------------------------
print("2. option tables match the original pack")
check(S.THRESHOLD_OPTIONS == [0.00001, 0.0001, 0.0002, 0.001, 0.002, 0.01],
      "THRESHOLD list")
check(S.RIM_OFFECT_OPTIONS == [0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.003,
                               0.004, 0.005, 0.01], "RIM_OFFECT list")
check(S.OUTLINE_COL_OPTIONS == [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9],
      "OUTLINE_COL list")
check(S.OUTLINE_MODE_OPTIONS == [1.0, -1.0], "OUTLINE_MODE INSIDE/OUTSIDE")
check(S.TEXTURE_OUTLINE_STRENGTH_OPTIONS == [0.0, 0.5, 0.8, 1.0, 1.5],
      "TEXTURE_OUTLINE_STRENGTH list")
check(S.OUTLINE_THICKNESS_OPTIONS == [0.5, 1.0, 1.5, 2.0, 3.0],
      "OUTLINE_THICKNESS list")
check(S.SHADOW_BRIGHTNESS_OPTIONS[0] == 0.0 and S.SHADOW_BRIGHTNESS_OPTIONS[-1] == 1.0
      and len(S.SHADOW_BRIGHTNESS_OPTIONS) == 21, "SHADOW_BRIGHTNESS 0..1 step .05")
check(S.BLOCK_LIGHT_INTENSITY_OPTIONS == [0.0, 0.25, 0.5, 0.75, 0.8, 0.85, 1.0,
                                          1.25, 1.5, 2.0], "BLOCK_LIGHT_INTENSITY list")
check(S.BLOCK_LIGHT_SHADOW_BOOST_OPTIONS == [1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5],
      "BLOCK_LIGHT_SHADOW_BOOST list")
check(S.SHININESS_OPTIONS == [0.0, 0.25, 0.5, 0.75, 1.0], "Shininess list")
check(S.SHADOW_MAP_RESOLUTION_OPTIONS == [512, 1024, 2048, 4096, 8192],
      "shadowMapResolution list")
check(len(S.SHADOW_DISTANCE_OPTIONS) == 16 and S.SHADOW_DISTANCE_OPTIONS[0] == -1.0,
      "SHADOW_DISTANCE list (-1 = AUTO)")

values = S.default_values()
for spec in S.CONTROLS:
    if spec["kind"] == "slider":
        idx = values[spec["key"]]
        check(0 <= idx < len(spec["options"]),
              "default in range: " + spec["key"])
    elif spec["kind"] == "dropdown":
        idx = values[spec["key"]]
        check(0 <= idx < len(spec["labels"]),
              "default in range: " + spec["key"])

check(S.outline_params(values) == (
    [0.0001, 0.001, 0.3, 1.0],
    [0.0, 0.0, 0.8, 0.5],
    [0.0, 0.0, 0.0, 0.0],
), "default outline uniforms match the pack defaults")
check(S.shadow_params(values) == (
    [0.0, 0.6, -1.0, 1.0],
    [1024.0, 0.8, 1.25, 0.0],
), "default shadow uniforms match the pack defaults")

# ---------------------------------------------------------------------------
# 3. settings page + post-process wiring
# ---------------------------------------------------------------------------
print("3. settings page and post-process wiring")
system = C.OutlineShaderNEClient("OutlineShaderNE", "OutlineShaderNEClient")
system.OnUiInitFinished({})

inst = FACTORY.window.instances.get(S.MOD_NAMESPACE)
check(inst is not None, "settings instance registered")
visible_controls = [c for c in S.CONTROLS if not c.get("hidden")]
check(len(inst.controls) == len(visible_controls),
      "all %d visible controls added (got %d)" % (len(visible_controls), len(inst.controls)))

post = FACTORY.post
check(post.order == [S.PROCESS_SHADOW, S.PROCESS_OUTLINE],
      "shadow pass added before outline pass: %s" % (post.order,))
check(post.enabled[S.PROCESS_OUTLINE] is True, "outline enabled by default")
check(post.enabled[S.PROCESS_SHADOW] is False,
      "shadow pass skipped by default (ENABLE_SHADOWS=OFF)")

check(post.params[(S.PROCESS_OUTLINE, "p_outline_a")] == [0.0001, 0.001, 0.3, 1.0],
      "outline params written")
check(post.params[(S.PROCESS_OUTLINE, "p_outline_b")] == [0.0, 0.0, 0.8, 0.5],
      "texture-outline params written")
check(post.params[(S.PROCESS_SHADOW, "p_shadow_a")] == [0.0, 0.6, -1.0, 1.0],
      "shadow params written")
check(post.params[(S.PROCESS_SHADOW, "p_shadow_b")] == [1024.0, 0.8, 1.25, 0.0],
      "block-light params written")

# simulate callbacks
system.OnControlChanged("OUTLINE_COL", 8)
check(post.params[(S.PROCESS_OUTLINE, "p_outline_a")][2] == 0.9,
      "OUTLINE_COL slider reaches the shader")

system.OnControlChanged("OUTLINE_MODE", 1)
check(post.params[(S.PROCESS_OUTLINE, "p_outline_a")][3] == -1.0,
      "OUTLINE_MODE OUTSIDE reaches the shader")

system.OnControlChanged("ENABLE_TEXTURE_OUTLINES", True)  # hidden: ignored
system.OnControlChanged("OUTLINE_THICKNESS", 4)            # hidden: ignored
check(post.params[(S.PROCESS_OUTLINE, "p_outline_b")] == [0.0, 0.0, 0.8, 0.5],
      "hidden texture-outline controls stay at their defaults")

system.OnControlChanged("ENABLE_SHADOWS", True)
check(post.enabled[S.PROCESS_SHADOW] is True, "shadow pass enabled by toggle")
system.OnControlChanged("SHADOW_BRIGHTNESS", 20)
check(post.params[(S.PROCESS_SHADOW, "p_shadow_a")][1] == 1.0,
      "SHADOW_BRIGHTNESS reaches the shader")
system.OnControlChanged("shadowMapResolution", 4)
check(post.params[(S.PROCESS_SHADOW, "p_shadow_b")][0] == 8192.0,
      "shadowMapResolution slider reaches the shader")

system.OnControlChanged("MASTER", False)
check(post.enabled[S.PROCESS_OUTLINE] is False and post.enabled[S.PROCESS_SHADOW] is False,
      "master switch disables both passes")

# ---------------------------------------------------------------------------
# 4. persistence
# ---------------------------------------------------------------------------
print("4. persistence and process descriptions")
system.OnControlChanged("MASTER", True)
system.OnControlChanged("CEL", True)
system.OnControlChanged("PAPER_WORLD", True)
for _ in range(20):
    system.OnScriptTickClient({})
saved = FACTORY.config.store
check(len(saved) == 1, "settings written to the config component")
reloaded = C.OutlineShaderNEClient("OutlineShaderNE", "OutlineShaderNEClient")
check(reloaded._values["CEL"] is True and reloaded._values["PAPER_WORLD"] is True,
      "config values restored on a new client system")
check(reloaded._values["OUTLINE_COL"] == 8, "slider index restored")

for values_dict in (S.default_values(), reloaded._values):
    desc = S.build_outline_process(values_dict)
    json.dumps(desc)
    check(len(desc["paras"]) == 3, "outline process has 3 vec4 params")
    check(desc["pass_array"][0]["depth_enable"] is True, "outline pass has depth")
    check(desc["pass_array"][0]["bindTexture"][0]["texture"] == S.CEL_RAMP_TEXTURE,
          "cel ramp bound to outline pass")
    shadow_desc = S.build_shadow_process(values_dict)
    json.dumps(shadow_desc)
    check(len(shadow_desc["paras"]) == 2, "shadow process has 2 vec4 params")

cel_ramp = os.path.join(RES_DIR, "textures", "outline_shader", "cel_ramp.png")
check(os.path.isfile(cel_ramp), "cel_ramp.png copied into the resource pack")
check(os.path.isdir(os.path.join(SCRIPT_DIR, "entities")),
      "behavior pack contains the entities/ marker required by NetEase")
material = json.load(io.open(MATERIAL, "r", encoding="utf-8"))
common = json.load(io.open(os.path.join(os.path.dirname(MATERIAL), "common.json"),
                           "r", encoding="utf-8"))
check(any(item.get("path") == "materials/postprocess.material" for item in common),
      "materials/common.json loads postprocess.material")
check(S.MATERIAL_OUTLINE in material and S.MATERIAL_SHADOW in material,
      "both post-process materials exist in postprocess.material")
check(material[S.MATERIAL_OUTLINE]["fragmentShader"].endswith("outline_shader_ne.fragment"),
      "outline material points at the ported shader")
check(material[S.MATERIAL_SHADOW]["fragmentShader"].endswith("shadow_shader_ne.fragment"),
      "shadow material points at the shadow shader")

print("")
if FAILURES:
    print("FAILED: %d check(s)" % len(FAILURES))
    for item in FAILURES:
        print("  - " + item)
    sys.exit(1)
print("ALL CHECKS PASSED")
