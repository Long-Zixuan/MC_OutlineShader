# -*- coding: utf-8 -*-
"""
Outline Shader NE - settings descriptor.

Every option list below is copied from the original shader pack:

    shaders/shaders.properties   (sliders / screen / screen.Shadow / ...)
    shaders/commonSettings.glsl  (#define defaults and option lists)
    shaders/final.fsh            (THRESHOLD / RIM_OFFECT / OUTLINE_COL / ...)

The values are stored as *option indexes* (0..len-1) because the NetEase
universal settings API only offers integer sliders.  ShaderParameters.py turns
an index back into the exact value from the original list.
"""

try:
    _STRING_TYPES = (basestring,)
    _INT_TYPES = (int, long)
    _UNICODE_TYPE = unicode
except NameError:  # pragma: no cover - the runtime is Python 2
    _STRING_TYPES = (str,)
    _INT_TYPES = (int,)
    _UNICODE_TYPE = str


def api_text(text):
    """NetEase's Python 2 binding expects UTF-8 encoded str, not unicode.

    Passing u"中文" directly to AddText/AddToggle/RegisterSettingInst can end up
    as an empty label on some SDK builds; encode it to UTF-8 bytes first.
    """
    if _UNICODE_TYPE is not str and isinstance(text, _UNICODE_TYPE):
        try:
            return text.encode("utf-8")
        except Exception:
            return text
    return text

MOD_NAMESPACE = "OutlineShaderNE"
MOD_DISPLAY_NAME = u"描边光影 Outline Shader"
MOD_ICON = "textures/outline_shader/icon"

CFG_NAME = "outline_shader_ne_settings_v1"

# Post-process effect names (also used by the Python PostProcess component)
PROCESS_OUTLINE = "outline_shader_ne_outline"
PROCESS_SHADOW = "outline_shader_ne_shadow"

# Materials declared in addon/OutlineShaderNE_Res/materials/postprocess.material
MATERIAL_OUTLINE = "outline_shader_ne_outline"
MATERIAL_SHADOW = "outline_shader_ne_shadow"
CEL_RAMP_TEXTURE = "textures/outline_shader/cel_ramp"

# ---------------------------------------------------------------------------
# Option lists - verbatim from the original pack
# ---------------------------------------------------------------------------
THRESHOLD_OPTIONS = [0.00001, 0.0001, 0.0002, 0.001, 0.002, 0.01]
RIM_OFFECT_OPTIONS = [0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.003, 0.004, 0.005, 0.01]
OUTLINE_COL_OPTIONS = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
OUTLINE_MODE_OPTIONS = [1.0, -1.0]           # INSIDE = 1, OUTSIDE = -1
OUTLINE_MODE_LABELS = ["INSIDE", "OUTSIDE"]

TEXTURE_OUTLINE_STRENGTH_OPTIONS = [0.0, 0.5, 0.8, 1.0, 1.5]
OUTLINE_THICKNESS_OPTIONS = [0.5, 1.0, 1.5, 2.0, 3.0]

SHININESS_OPTIONS = [0.0, 0.25, 0.5, 0.75, 1.0]

SHADOW_BRIGHTNESS_OPTIONS = [round(i * 0.05, 2) for i in range(21)]
BLOCK_LIGHT_INTENSITY_OPTIONS = [0.0, 0.25, 0.5, 0.75, 0.8, 0.85, 1.0, 1.25, 1.5, 2.0]
BLOCK_LIGHT_SHADOW_BOOST_OPTIONS = [1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5]

SHADOW_MAP_RESOLUTION_OPTIONS = [512, 1024, 2048, 4096, 8192]
SHADOW_MAP_RESOLUTION_LABELS = ["512", "1024", "2048", "4096", "8192"]

SHADOW_DISTANCE_OPTIONS = [
    -1.0, 64.0, 96.0, 128.0, 160.0, 192.0, 224.0, 256.0,
    288.0, 320.0, 352.0, 384.0, 416.0, 448.0, 480.0, 512.0,
]
SHADOW_DISTANCE_LABELS = [
    "AUTO (-1)", "64", "96", "128", "160", "192", "224", "256",
    "288", "320", "352", "384", "416", "448", "480", "512",
]

# ---------------------------------------------------------------------------
# UI controls.  Order here == order in the settings page.
#   kind: text | toggle | slider | dropdown
#   default: bool for toggle, option index for slider/dropdown
# ---------------------------------------------------------------------------
CONTROLS = [
    {"kind": "text", "key": "sec_main", "label": u"—— 总开关 / Master ——"},

    {"kind": "toggle", "key": "MASTER", "label": u"启用描边光影 / Enable",
     "default": True},

    {"kind": "text", "key": "sec_outline", "label": u"—— 描边 / Outline ——"},

    {"kind": "slider", "key": "THRESHOLD", "label": u"描边阈值 / THRESHOLD",
     "options": THRESHOLD_OPTIONS, "default": 1},

    {"kind": "text", "key": "legend_threshold",
     "label": u"阈值档位：0=1e-5  1=1e-4  2=2e-4  3=1e-3  4=2e-3  5=1e-2"},

    {"kind": "slider", "key": "RIM_OFFECT", "label": u"描边偏移 / RIM_OFFECT",
     "options": RIM_OFFECT_OPTIONS, "default": 3},

    {"kind": "text", "key": "legend_rim",
     "label": u"偏移档位：0=.0001 1=.0002 2=.0005 3=.001 4=.002 5=.003 6=.004 7=.005 8=.01"},

    {"kind": "slider", "key": "OUTLINE_COL", "label": u"描边颜色 / OUTLINE_COL",
     "options": OUTLINE_COL_OPTIONS, "default": 2},

    {"kind": "text", "key": "legend_col",
     "label": u"颜色档位：0=.1 1=.2 2=.3 3=.4 4=.5 5=.6 6=.7 7=.8 8=.9"},

    {"kind": "slider", "key": "OUTLINE_MODE", "label": u"描边模式 / OUTLINE_MODE",
     "options": OUTLINE_MODE_OPTIONS, "default": 0},

    {"kind": "text", "key": "legend_mode",
     "label": u"模式档位：0=INSIDE  1=OUTSIDE"},

    {"kind": "toggle", "key": "LINEAR_DEPTH", "label": u"线性深度 / LINEAR_DEPTH",
     "default": False},

    # 纹理描边相关控件从界面隐藏；参数仍保留默认值（默认关闭）。
    # 需要时把 hidden 去掉即可重新显示。
    {"kind": "text", "key": "sec_texture", "hidden": True,
     "label": u"—— 纹理描边 / Texture Outline ——"},

    {"kind": "toggle", "key": "ENABLE_TEXTURE_OUTLINES", "hidden": True,
     "label": u"启用纹理描边 / ENABLE_TEXTURE_OUTLINES", "default": False},

    {"kind": "slider", "key": "TEXTURE_OUTLINE_STRENGTH", "hidden": True,
     "label": u"纹理描边强度 / TEXTURE_OUTLINE_STRENGTH",
     "options": TEXTURE_OUTLINE_STRENGTH_OPTIONS, "default": 2},

    {"kind": "text", "key": "legend_strength", "hidden": True,
     "label": u"强度档位：0=0  1=.5  2=.8  3=1.0  4=1.5"},

    {"kind": "slider", "key": "OUTLINE_THICKNESS", "hidden": True,
     "label": u"描边粗细 / OUTLINE_THICKNESS",
     "options": OUTLINE_THICKNESS_OPTIONS, "default": 0},

    {"kind": "text", "key": "legend_thickness", "hidden": True,
     "label": u"粗细档位：0=.5  1=1.0  2=1.5  3=2.0  4=3.0"},

    {"kind": "text", "key": "sec_style", "label": u"—— 风格化 / Style ——"},

    {"kind": "toggle", "key": "CEL", "label": u"卡通渲染 / CEL", "default": False},

    {"kind": "toggle", "key": "PAPER_WORLD", "label": u"纸世界 / PAPER_WORLD",
     "default": False},

    {"kind": "slider", "key": "Shininess", "label": u"水面高光 / Shininess",
     "options": SHININESS_OPTIONS, "default": 0},

    {"kind": "text", "key": "legend_shininess",
     "label": u"高光档位：0=0  1=.25  2=.5  3=.75  4=1.0"},

    {"kind": "text", "key": "sec_shadow",
     "label": u"—— 阴影 / Shadow（网易版为屏幕空间近似）——"},

    {"kind": "toggle", "key": "ENABLE_SHADOWS", "label": u"启用阴影 / ENABLE_SHADOWS",
     "default": False},

    {"kind": "toggle", "key": "SOFT_SHADOWS", "label": u"软阴影 / SOFT_SHADOWS",
     "default": True},

    # 下拉框在部分 SDK 上选中文本会空白，统一改成整数滑条 + 档位说明。
    {"kind": "slider", "key": "shadowMapResolution",
     "label": u"阴影分辨率 / shadowMapResolution",
     "options": SHADOW_MAP_RESOLUTION_OPTIONS, "default": 1},

    {"kind": "text", "key": "legend_resolution",
     "label": u"分辨率档位：0=512  1=1024  2=2048  3=4096  4=8192"},

    {"kind": "slider", "key": "SHADOW_DISTANCE",
     "label": u"阴影距离 / SHADOW_DISTANCE",
     "options": SHADOW_DISTANCE_OPTIONS, "default": 0},

    {"kind": "text", "key": "legend_distance",
     "label": u"距离档位：0=AUTO  1=64  2=96  3=128 … 15=512"},

    {"kind": "slider", "key": "SHADOW_BRIGHTNESS",
     "label": u"阴影亮度 / SHADOW_BRIGHTNESS",
     "options": SHADOW_BRIGHTNESS_OPTIONS, "default": 12},

    {"kind": "text", "key": "legend_brightness",
     "label": u"亮度档位：0=.00  4=.20  8=.40  12=.60  16=.80  20=1.00"},

    {"kind": "slider", "key": "BLOCK_LIGHT_INTENSITY",
     "label": u"方块光强度 / BLOCK_LIGHT_INTENSITY",
     "options": BLOCK_LIGHT_INTENSITY_OPTIONS, "default": 4},

    {"kind": "text", "key": "legend_block",
     "label": u"方块光档位：0=0 1=.25 2=.5 3=.75 4=.8 5=.85 6=1 7=1.25 8=1.5 9=2"},

    {"kind": "slider", "key": "BLOCK_LIGHT_SHADOW_BOOST",
     "label": u"方块光阴影增强 / BLOCK_LIGHT_SHADOW_BOOST",
     "options": BLOCK_LIGHT_SHADOW_BOOST_OPTIONS, "default": 2},

    {"kind": "text", "key": "legend_boost",
     "label": u"增强档位：0=1  1=1.1  2=1.25  3=1.5  4=1.75  5=2  6=2.5"},

    {"kind": "text", "key": "sec_note_1",
     "label": u"说明：网易版渲染器不提供阴影贴图，阴影项由深度屏幕空间近似实现。"},

    {"kind": "text", "key": "sec_note_2",
     "label": u"描边算法与原版 final.fsh 完全一致；参数改动会即时生效。"},

    # 底部品牌区。官方通用设置页不支持插入图片，logo 用作本模组的设置页/
    # 模组列表图标（textures/outline_shader/icon.png），这里放文字签名。
    {"kind": "text", "key": "footer_brand", "label": u"LONGY SOFTWARE"},

    {"kind": "text", "key": "footer_product",
     "label": u"Outline Shader · LZX.Celluloid.Project"},
]

CONTROL_MAP = {}
for _c in CONTROLS:
    CONTROL_MAP[_c["key"]] = _c


def default_values():
    values = {}
    for spec in CONTROLS:
        if spec["kind"] == "text":
            continue
        values[spec["key"]] = spec["default"]
    return values


def option_value(spec, index):
    """Index -> value from the original option list."""
    options = spec.get("options")
    if options is None:
        options = spec.get("labels") or [0.0]
    try:
        index = int(index)
    except (TypeError, ValueError):
        index = 0
    if index < 0:
        index = 0
    if index >= len(options):
        index = len(options) - 1
    return options[index]


def dropdown_index(spec, value):
    """The callback/Get*Value result may be an index (int), a label or a number."""
    labels = spec["labels"]
    if isinstance(value, bool):
        return 0
    if isinstance(value, _INT_TYPES):
        index = int(value)
    elif isinstance(value, float):
        index = int(value)
    elif isinstance(value, _STRING_TYPES):
        if value in labels:
            return labels.index(value)
        try:
            index = int(value)
        except (TypeError, ValueError):
            # Some builds return the option text for GetDropDownValue; match it.
            if value in labels:
                return labels.index(value)
            return 0
    else:
        return 0
    if index < 0:
        index = 0
    if index >= len(labels):
        index = len(labels) - 1
    return index


def bool_value(value):
    if isinstance(value, _STRING_TYPES):
        return value.lower() in ("1", "true", "yes", "on")
    return bool(value)


# ---------------------------------------------------------------------------
# Values -> shader uniforms
# ---------------------------------------------------------------------------
def outline_params(values):
    """EXTRA_VECTOR1..3 for outline_shader_ne.fragment."""
    vector1 = [
        float(option_value(CONTROL_MAP["THRESHOLD"], values["THRESHOLD"])),
        float(option_value(CONTROL_MAP["RIM_OFFECT"], values["RIM_OFFECT"])),
        float(option_value(CONTROL_MAP["OUTLINE_COL"], values["OUTLINE_COL"])),
        float(option_value(CONTROL_MAP["OUTLINE_MODE"], values["OUTLINE_MODE"])),
    ]
    vector2 = [
        1.0 if bool_value(values["LINEAR_DEPTH"]) else 0.0,
        1.0 if bool_value(values["ENABLE_TEXTURE_OUTLINES"]) else 0.0,
        float(option_value(CONTROL_MAP["TEXTURE_OUTLINE_STRENGTH"],
                           values["TEXTURE_OUTLINE_STRENGTH"])),
        float(option_value(CONTROL_MAP["OUTLINE_THICKNESS"],
                           values["OUTLINE_THICKNESS"])),
    ]
    vector3 = [
        1.0 if bool_value(values["CEL"]) else 0.0,
        1.0 if bool_value(values["PAPER_WORLD"]) else 0.0,
        0.0,
        0.0,
    ]
    return vector1, vector2, vector3


def shadow_params(values):
    """EXTRA_VECTOR1..2 for shadow_shader_ne.fragment."""
    vector1 = [
        1.0 if bool_value(values["ENABLE_SHADOWS"]) else 0.0,
        float(option_value(CONTROL_MAP["SHADOW_BRIGHTNESS"], values["SHADOW_BRIGHTNESS"])),
        float(option_value(CONTROL_MAP["SHADOW_DISTANCE"], values["SHADOW_DISTANCE"])),
        1.0 if bool_value(values["SOFT_SHADOWS"]) else 0.0,
    ]
    vector2 = [
        float(option_value(CONTROL_MAP["shadowMapResolution"],
                           values["shadowMapResolution"])),
        float(option_value(CONTROL_MAP["BLOCK_LIGHT_INTENSITY"],
                           values["BLOCK_LIGHT_INTENSITY"])),
        float(option_value(CONTROL_MAP["BLOCK_LIGHT_SHADOW_BOOST"],
                           values["BLOCK_LIGHT_SHADOW_BOOST"])),
        float(option_value(CONTROL_MAP["Shininess"], values["Shininess"])),
    ]
    return vector1, vector2


def build_outline_process(values):
    vector1, vector2, vector3 = outline_params(values)
    return {
        "name": PROCESS_OUTLINE,
        "enable": True,
        "paras": [
            {"name": "p_outline_a", "value": vector1, "range": [-2000.0, 2000.0]},
            {"name": "p_outline_b", "value": vector2, "range": [0.0, 8.0]},
            {"name": "p_outline_c", "value": vector3, "range": [0.0, 1.0]},
        ],
        "pass_array": [
            {
                "render_target": {"width": 1.0, "height": 1.0},
                "material": MATERIAL_OUTLINE,
                "depth_enable": True,
                "bindTexture": [
                    {"texture": CEL_RAMP_TEXTURE},
                ],
            }
        ],
    }


def build_shadow_process(values):
    vector1, vector2 = shadow_params(values)
    return {
        "name": PROCESS_SHADOW,
        "enable": True,
        "paras": [
            {"name": "p_shadow_a", "value": vector1, "range": [-1.0, 8192.0]},
            {"name": "p_shadow_b", "value": vector2, "range": [0.0, 8192.0]},
        ],
        "pass_array": [
            {
                "render_target": {"width": 1.0, "height": 1.0},
                "material": MATERIAL_SHADOW,
                "depth_enable": True,
            }
        ],
    }
