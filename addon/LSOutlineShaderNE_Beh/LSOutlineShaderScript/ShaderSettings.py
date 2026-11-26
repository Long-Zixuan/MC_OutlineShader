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

MOD_NAMESPACE = "LSOutlineShaderNE"
MOD_DISPLAY_NAME = u"描边光影"
MOD_ICON = "textures/ls_outline_shader/icon"

CFG_NAME = "ls_outline_shader_ne_settings_v1"

# Post-process effect names (also used by the Python PostProcess component)
PROCESS_OUTLINE = "ls_outline_shader_ne_outline"

# Materials declared in addon/LSOutlineShaderNE_Res/materials/postprocess.material
MATERIAL_OUTLINE = "ls_outline_shader_ne_outline"
CEL_RAMP_TEXTURE = "textures/ls_outline_shader/cel_ramp"

# ---------------------------------------------------------------------------
# Option lists - verbatim from the original pack
# ---------------------------------------------------------------------------
THRESHOLD_OPTIONS = [0.00001, 0.0001, 0.0002, 0.001, 0.002, 0.01]
RIM_OFFECT_OPTIONS = [0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.003, 0.004, 0.005, 0.01]
OUTLINE_COL_OPTIONS = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
OUTLINE_MODE_OPTIONS = [1.0, -1.0]           # INSIDE = 1, OUTSIDE = -1
OUTLINE_MODE_LABELS = ["INSIDE", "OUTSIDE"]

SHININESS_OPTIONS = [0.0, 0.25, 0.5, 0.75, 1.0]

IS_LOW_HEALTH = False
IS_SURVIVAL = False

# ---------------------------------------------------------------------------
# UI controls.  Order here == order in the settings page.
#   kind: text | toggle | slider | dropdown
#   default: bool for toggle, option index for slider/dropdown
# ---------------------------------------------------------------------------
CONTROLS = [
    {"kind": "toggle", "key": "MASTER", "label": u"启用描边光影",
     "default": True},

    {"kind": "text", "key": "sec_outline", "label": u"描边"},

    {"kind": "slider", "key": "THRESHOLD", "label": u"描边阈值",
     "options": THRESHOLD_OPTIONS, "default": 1},

    {"kind": "slider", "key": "RIM_OFFECT", "label": u"描边偏移",
     "options": RIM_OFFECT_OPTIONS, "default": 3},

    {"kind": "slider", "key": "OUTLINE_COL", "label": u"描边颜色",
     "options": OUTLINE_COL_OPTIONS, "default": 2},

    {"kind": "slider", "key": "OUTLINE_MODE", "hidden": True,
     "label": u"描边模式", "options": OUTLINE_MODE_OPTIONS, "default": 0},

    {"kind": "text", "key": "sec_mode", "label": u"描边模式"},

    {"kind": "toggle", "key": "OUTLINE_MODE_INSIDE", "label": u"内侧",
     "default": True},

    {"kind": "toggle", "key": "OUTLINE_MODE_OUTSIDE", "label": u"外侧",
     "default": False},

    {"kind": "toggle", "key": "LINEAR_DEPTH", "label": u"线性深度",
     "default": True},

    {"kind": "text", "key": "sec_style", "label": u"风格"},

    {"kind": "toggle", "key": "CEL", "label": u"卡通渲染", "default": False},

    {"kind": "toggle", "key": "PAPER_WORLD", "label": u"纸世界",
     "default": False},

    {"kind": "slider", "key": "Shininess", "label": u"水面高光",
     "options": SHININESS_OPTIONS, "default": 0},

    {"kind": "text", "key": "footer_brand", "label": u"LoongLy Software 2026"},
]

CONTROL_MAP = {}
for _c in CONTROLS:
    CONTROL_MAP[_c["key"]] = _c

# ---------------------------------------------------------------------------
# Custom settings UI (JSON UI + ScreenNode)
# ---------------------------------------------------------------------------
UI_KEY = "ls_outline_shader_settings"
UI_NAMESPACE = "ls_outline_shader"
UI_JSON_DEF = UI_NAMESPACE + ".main"

# (kind, key) rows shown in the custom panel.  "header" is a section title,
# "mode" is the 内侧/外侧 option pair.
UI_ROWS = [
    ("toggle", "MASTER"),
    ("header", u"描边"),
    ("number", "THRESHOLD"),
    ("number", "RIM_OFFECT"),
    ("number", "OUTLINE_COL"),
    ("mode", "OUTLINE_MODE"),
    ("toggle", "LINEAR_DEPTH"),
    ("header", u"风格"),
    ("toggle", "CEL"),
    ("toggle", "PAPER_WORLD"),
    ("number", "Shininess"),
]

UI_NUMBER_KEYS = [key for kind, key in UI_ROWS if kind == "number"]
UI_TOGGLE_KEYS = [key for kind, key in UI_ROWS if kind == "toggle"]


def format_value(key, value):
    """Human-readable value for the custom UI labels."""
    if key == "OUTLINE_COL":
        return ("%.1f" % value).rstrip("0").rstrip(".")
    if abs(value) < 1.0:
        text = "%.5f" % value
        return text.rstrip("0").rstrip(".")
    return ("%.2f" % value).rstrip("0").rstrip(".")



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
    """EXTRA_VECTOR1..3 for ls_outline_shader_ne.fragment."""
    vector1 = [
        float(option_value(CONTROL_MAP["THRESHOLD"], values["THRESHOLD"])),
        float(option_value(CONTROL_MAP["RIM_OFFECT"], values["RIM_OFFECT"])),
        float(option_value(CONTROL_MAP["OUTLINE_COL"], values["OUTLINE_COL"])),
        float(option_value(CONTROL_MAP["OUTLINE_MODE"], values["OUTLINE_MODE"])),
    ]
    vector2 = [
        1.0 if bool_value(values["LINEAR_DEPTH"]) else 0.0,
        0.0,
        0.0,
        0.0,
    ]
    vector3 = [
        1.0 if bool_value(values["CEL"]) else 0.0,
        1.0 if bool_value(values["PAPER_WORLD"]) else 0.0,
        1.0 if IS_LOW_HEALTH else 0.0, #IS_LOW_HEALTH
        1.0 if IS_SURVIVAL else 0.0,
    ]
    return vector1, vector2, vector3


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
