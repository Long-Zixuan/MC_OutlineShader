# -*- coding: utf-8 -*-
"""
Outline Shader NE - custom settings screen.

A transparent overlay: a semi-transparent panel on the right, the game is
visible on the left, every value is shown as text and changed with +/- buttons.
Opened with PushScreen() from the "打开设置" button on the universal settings page.

The UI JSON is resource_pack/ui/settings_ui.json (namespace ls_outline_shader).
"""

import mod.client.extraClientApi as clientApi

from LSOutlineShaderScript import ShaderSettings as S

ScreenNode = clientApi.GetScreenNodeCls()

# Set by LSOutlineShaderNEClient before PushScreen().
HOST = None


class LSOutlineShaderUIScreen(ScreenNode):

    def __init__(self, namespace, name, params):
        ScreenNode.__init__(self, namespace, name, params)
        self._bound = False
        self._content = None

    # --------------------------------------------------------------- scroll path
    def GetContent(self):
        """Return the stack panel that holds the rows."""
        if self._content is not None:
            return self._content

        control = self.GetBaseUIControl("/settings_panel/settings_rows")
        if control is not None:
            self._content = control
            return control

        scroll_paths = [
            "/settings_panel/settings_scroll",
            "/settings_panel/settings_scroll/scroll_view",
            "/settings_panel/settings_scroll/scroll_view_port",
            "/settings_panel/settings_scroll/scroll_view/scroll_view_port",
            "/settings_panel/settings_scroll/scroll_view_port/scroll_view",
        ]
        for path in scroll_paths:
            control = self.GetBaseUIControl(path)
            if control is None:
                continue
            scroll_view = control.asScrollView()
            if scroll_view is None:
                continue
            content = scroll_view.GetScrollViewContentControl()
            if content is not None:
                self._content = content
                return content

        content_paths = [
            "/settings_panel/settings_scroll/settings_content",
            "/settings_panel/settings_scroll/scroll_view/settings_content",
            "/settings_panel/settings_scroll/scroll_view_port/settings_content",
            "/settings_panel/settings_scroll/scroll_view/scroll_view_port/settings_content",
            "/settings_panel/settings_scroll/scroll_view_port/scroll_view/settings_content",
            "/settings_panel/settings_content",
        ]
        for path in content_paths:
            control = self.GetBaseUIControl(path)
            if control is not None:
                self._content = control
                return control
        return None

    def GetControl(self, path):
        name = str(path).replace("\\", "/").rstrip("/").split("/")[-1]
        content = self.GetContent()
        if content is not None:
            containers = [content]
            inner = content.GetChildByName("settings_content")
            if inner is None:
                inner = content.GetChildByPath("/settings_content")
            if inner is not None:
                containers.append(inner)
            for container in containers:
                control = container.GetChildByName(name)
                if control is None:
                    control = container.GetChildByPath("/" + name)
                if control is not None:
                    return control

            row_name = None
            if name.startswith("dec_") or name.startswith("inc_") or name.startswith("val_"):
                row_name = "row_" + name.split("_", 1)[1]
            elif name.startswith("toggle_"):
                row_name = "row_" + name[7:]
            elif name.startswith("mode_"):
                row_name = "row_OUTLINE_MODE"
            if row_name:
                row = content.GetChildByName(row_name)
                if row is not None:
                    control = row.GetChildByName(name)
                    if control is None:
                        control = row.GetChildByPath("/" + name)
                    if control is not None:
                        return control
        for prefix in (
            "/settings_panel/settings_scroll/settings_content",
            "/settings_panel/settings_scroll/scroll_view/settings_content",
            "/settings_panel/settings_scroll/scroll_view_port/settings_content",
            "/settings_panel/settings_content",
        ):
            control = self.GetBaseUIControl(prefix + "/" + name)
            if control is not None:
                return control
        return self.GetBaseUIControl(path)

    # ------------------------------------------------------------------ binding
    def Create(self):
        self.BindButtons()
        self.Refresh()
        print("[LSOutlineShaderNE] custom UI created")

    def BindButtons(self):
        content = self.GetContent()
        print("[LSOutlineShaderNE] rows content: %s" % (content is not None))
        paths = ["/settings_panel/close"]
        for key in S.UI_NUMBER_KEYS:
            paths.append("/settings_panel/dec_" + key)
            paths.append("/settings_panel/inc_" + key)
        for key in S.UI_TOGGLE_KEYS:
            paths.append("/settings_panel/toggle_" + key)
        paths.append("/settings_panel/mode_INSIDE")
        paths.append("/settings_panel/mode_OUTSIDE")

        for path in paths:
            control = self.GetControl(path)
            if control is None:
                print("[LSOutlineShaderNE] UI control missing: %s" % path)
                continue
            button = control.asButton()
            if button is None:
                print("[LSOutlineShaderNE] UI control is not a button: %s" % path)
                continue
            button.AddTouchEventParams({"isSwallow": True})
            button.SetButtonTouchUpCallback(self.OnButtonUp)
        self._bound = True

    # ------------------------------------------------------------------- events
    def OnButtonUp(self, *args):
        data = args[0] if args else {}
        path = ""
        if isinstance(data, dict):
            path = data.get("ButtonPath", "") or data.get("#ButtonPath", "")
        name = str(path).replace("\\", "/").rstrip("/").split("/")[-1]

        if name == "close":
            if HOST is not None:
                HOST.CloseCustomUI()
                return
            closed = False
            try:
                closed = clientApi.PopTopUI()
            except Exception:
                pass
            if not closed:
                self.SetRemove()
            return
        if name.startswith("dec_"):
            self.Step(name[4:], -1)
        elif name.startswith("inc_"):
            self.Step(name[4:], 1)
        elif name.startswith("toggle_"):
            self.Toggle(name[7:])
        elif name.startswith("mode_"):
            self.SetMode(name == "mode_OUTSIDE")

    # ------------------------------------------------------------------ actions
    def Step(self, key, delta):
        if HOST is None:
            return
        spec = S.CONTROL_MAP.get(key)
        if spec is None or "options" not in spec:
            return
        options = spec["options"]
        values = HOST.get_ui_values()
        index = int(values.get(key, spec.get("default", 0)))
        index = max(0, min(index + delta, len(options) - 1))
        HOST.set_ui_value(key, index)
        self.RefreshNumber(key, index)

    def Toggle(self, key):
        if HOST is None:
            return
        values = HOST.get_ui_values()
        enabled = not S.bool_value(values.get(key, False))
        HOST.set_ui_value(key, enabled)
        self.RefreshToggle(key, enabled)

    def SetMode(self, outside):
        if HOST is None:
            return
        HOST.set_ui_mode(outside)
        self.RefreshMode(outside)

    # ------------------------------------------------------------------ refresh
    def Refresh(self):
        values = HOST.get_ui_values() if HOST is not None else S.default_values()

        for key in S.UI_NUMBER_KEYS:
            try:
                index = int(values.get(key, 0))
            except (TypeError, ValueError):
                index = 0
            self.RefreshNumber(key, index)

        for key in S.UI_TOGGLE_KEYS:
            self.RefreshToggle(key, S.bool_value(values.get(key, False)))

        try:
            mode = int(values.get("OUTLINE_MODE", 0))
        except (TypeError, ValueError):
            mode = 0
        self.RefreshMode(mode == 1)

    def RefreshNumber(self, key, index):
        spec = S.CONTROL_MAP.get(key)
        if spec is None:
            return
        value = S.option_value(spec, index)
        self.SetLabel("/settings_panel/val_" + key, S.format_value(key, value))

    def RefreshToggle(self, key, enabled):
        self.SetButtonText("/settings_panel/toggle_" + key,
                           u"开" if enabled else u"关")

    def RefreshMode(self, outside):
        self.SetButtonText("/settings_panel/mode_INSIDE",
                           u"● 内侧" if not outside else u"内侧")
        self.SetButtonText("/settings_panel/mode_OUTSIDE",
                           u"● 外侧" if outside else u"外侧")

    # ------------------------------------------------------------------ helpers
    def SetLabel(self, path, text):
        control = self.GetControl(path)
        if control is None:
            return
        label = control.asLabel()
        if label is not None:
            label.SetText(S.api_text(text))

    def SetButtonText(self, path, text):
        button = self.GetControl(path)
        if button is None:
            return
        label = None
        for child_name in ("button_label", "label"):
            label = button.GetChildByName(child_name)
            if label is not None:
                break
        if label is None:
            label = button.GetChildByPath("/button_label")
        if label is None:
            return
        label = label.asLabel()
        if label is not None:
            label.SetText(S.api_text(text))
