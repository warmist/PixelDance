#include "limgui.h"

#include <imgui.h>
#include <vector>

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"
int lua_absindex(lua_State *L, int i) {
	if (i < 0 && i > LUA_REGISTRYINDEX)
		i += lua_gettop(L) + 1;
	return i;
}
void lua_seti(lua_State *L, int index, lua_Integer i) {
	luaL_checkstack(L, 1, "not enough stack slots available");
	index =  lua_absindex(L, index);
	lua_pushinteger(L, i);
	lua_insert(L, -2);
	lua_settable(L, index);
}

bool l_getfield(lua_State* L,int id,const char* fname) 
{
	lua_getfield(L, id, fname);
	if (lua_isnil(L, -1))
	{
		lua_pop(L, 1);
		return false;
	}
	return true;
}
bool get_size(lua_State*L,int arg,ImVec2& v)
{
	
    if (!lua_istable(L, arg))
    {
        luaL_error(L, "Expected size table for arg %d.",arg);
    }
    if (l_getfield(L, arg, "x"))
    {
        v.x = lua_tonumber(L, -1);
        if (!l_getfield(L, arg, "y"))
        {
            v.y = 0;
        }
        else
        {
            v.y = lua_tonumber(L, -1);
        }
        return true;
    }
    else
    {
		lua_pop(L, 1);
        lua_pushnumber(L, 1);
        lua_gettable(L, arg);
        v.x = lua_tonumber(L, -1);
        lua_pushnumber(L, 2);
        lua_gettable(L, arg);
        v.y = lua_tonumber(L, -1);
        return true;
    }
}


void get_color(lua_State*L, int idx, float color[], int num)
{
    luaL_checktype(L, idx, LUA_TTABLE);
    for (int i = 1; i <= num; i++)
    {
        lua_rawgeti(L, idx, i);
        if (lua_isnil(L, -1)){
            if (i == 4)
            {
                color[3] = 1;
            }
            lua_pop(L, 1);
            break;
        }
        color[i - 1] = lua_tonumber(L, -1);
        lua_pop(L, 1);
    }
}
void set_color(lua_State*L, float color[], int num)
{
    lua_newtable(L);
    for (int i = 1; i <= num; i++)
    {
        lua_pushnumber(L, color[i - 1]);
        lua_seti(L, -2, i);
    }
}
//bool          ColorButton(const char* desc_id, const ImVec4& col, ImGuiColorEditFlags flags = 0, ImVec2 size = ImVec2(0, 0));
static int l_color_button(lua_State* L)
{
    float col[4];
	const char* desc = luaL_checkstring(L, 1);
	get_color(L, 2, col, 4);
    int flags= luaL_optint(L, 3, 0);
	
	ImVec2 size;
	if (lua_istable(L, 4))
		get_size(L, 4, size);
	else
		size = { 0,0 };
    bool ret = ImGui::ColorButton(desc, ImVec4(col[0],col[1],col[2],col[3]),flags, size);
    lua_pushboolean(L, ret);
    return 1;
}
//IMGUI_API bool          ColorEdit3(const char* label, float col[3]);
static int l_color_edit3(lua_State* L)
{
    const char *label = luaL_checkstring(L, 1);
    float col[3];
    get_color(L, 2, col, 3);
    bool ret = ImGui::ColorEdit3(label, col);
    lua_pushboolean(L, ret);
    set_color(L, col, 3);
    return 2;
}
//IMGUI_API bool          ColorEdit4(const char* label, float col[4], bool show_alpha = true);
static int l_color_edit4(lua_State* L)
{
    const char *label = luaL_checkstring(L, 1);
    float col[4];
    get_color(L, 2, col, 4);
    bool show_alpha = lua_toboolean(L, 3);
    bool ret = ImGui::ColorEdit4(label, col,show_alpha);
    lua_pushboolean(L, ret);
    set_color(L, col, 4);
    return 2;
}
/*
IMGUI_API void          PlotLines(const char* label, const float* values, int values_count, int values_offset = 0, const char* overlay_text = NULL, float scale_min = FLT_MAX, float scale_max = FLT_MAX, ImVec2 graph_size = ImVec2(0,0), size_t stride = sizeof(float));
*/
static int l_plot_lines(lua_State* L)
{
    const char *label=luaL_checkstring(L,1);
    float *values=nullptr;
    int values_count=0;
    if ((lua_type(L, 2) == 10) /*cdata*/ || (lua_type(L, 2) == LUA_TLIGHTUSERDATA))
    {
        values = (float*)lua_topointer(L, 2);
        values_count = luaL_checkinteger(L,3);
    }
    else
    {
        luaL_error(L, "Invalid values");
    }
    ImGui::PlotLines(label,values, values_count,0,0,FLT_MAX,FLT_MAX,ImVec2(0,80));
    return 0;
}
/*
IMGUI_API void          PlotLines(const char* label, float (*values_getter)(void* data, int idx), void* data, int values_count, int values_offset = 0, const char* overlay_text = NULL, float scale_min = FLT_MAX, float scale_max = FLT_MAX, ImVec2 graph_size = ImVec2(0,0));
IMGUI_API void          PlotHistogram(const char* label, const float* values, int values_count, int values_offset = 0, const char* overlay_text = NULL, float scale_min = FLT_MAX, float scale_max = FLT_MAX, ImVec2 graph_size = ImVec2(0,0), size_t stride = sizeof(float));
IMGUI_API void          PlotHistogram(const char* label, float (*values_getter)(void* data, int idx), void* data, int values_count, int values_offset = 0, const char* overlay_text = NULL, float scale_min = FLT_MAX, float scale_max = FLT_MAX, ImVec2 graph_size = ImVec2(0,0));



// Widgets: Drags (tip: ctrl+click on a drag box to input text)
// ImGui 1.38+ work-in-progress, may change name or API.
IMGUI_API bool          DragFloat(const char* label, float* v, float v_step = 1.0f, float v_min = 0.0f, float v_max = 0.0f, const char* display_format = "%.3f");   // If v_max >= v_max we have no bound
IMGUI_API bool          DragInt(const char* label, int* v, int v_step = 1, int v_min = 0, int v_max = 0, const char* display_format = "%.0f");                // If v_max >= v_max we have no bound

// Widgets: Input
*/

//IMGUI_API bool          InputText(const char* label, char* buf, size_t buf_size, ImGuiInputTextFlags flags = 0, ImGuiTextEditCallback callback = NULL, void* user_data = NULL);
static int l_input_text(lua_State* L)
{
    const char *label = luaL_checkstring(L, 1);
    const char *str = luaL_checkstring(L, 2);
    int flags = luaL_optinteger(L, 3, 0);
    char buffer[256] = { 0 };
    memcpy_s(buffer, 255, str, strlen(str));
    bool ret = ImGui::InputText(label, buffer, 255, flags);
    lua_pushboolean(L, ret);
    lua_pushstring(L, buffer);
    return 2;
}
/*
IMGUI_API bool          InputFloat(const char* label, float* v, float step = 0.0f, float step_fast = 0.0f, int decimal_precision = -1, ImGuiInputTextFlags extra_flags = 0);
IMGUI_API bool          InputFloat2(const char* label, float v[2], int decimal_precision = -1);
IMGUI_API bool          InputFloat3(const char* label, float v[3], int decimal_precision = -1);
IMGUI_API bool          InputFloat4(const char* label, float v[4], int decimal_precision = -1);
IMGUI_API bool          InputInt(const char* label, int* v, int step = 1, int step_fast = 100, ImGuiInputTextFlags extra_flags = 0);
IMGUI_API bool          InputInt2(const char* label, int v[2]);
IMGUI_API bool          InputInt3(const char* label, int v[3]);
IMGUI_API bool          InputInt4(const char* label, int v[4]);

// Widgets: Trees
IMGUI_API bool          TreeNode(const char* str_label_id);                                 // if returning 'true' the node is open and the user is responsible for calling TreePop
IMGUI_API bool          TreeNode(const char* str_id, const char* fmt, ...);                 // "
IMGUI_API bool          TreeNode(const void* ptr_id, const char* fmt, ...);                 // "
IMGUI_API bool          TreeNodeV(const char* str_id, const char* fmt, va_list args);       // "
IMGUI_API bool          TreeNodeV(const void* ptr_id, const char* fmt, va_list args);       // "
IMGUI_API void          TreePush(const char* str_id = NULL);                                // already called by TreeNode(), but you can call Push/Pop yourself for layouting purpose
IMGUI_API void          TreePush(const void* ptr_id = NULL);                                // "
IMGUI_API void          TreePop();
IMGUI_API void          SetNextTreeNodeOpened(bool opened, ImGuiSetCond cond = 0);          // set next tree node to be opened.

// Widgets: Selectable / Lists
IMGUI_API bool          Selectable(const char* label, bool selected = false, const ImVec2& size = ImVec2(0,0));
IMGUI_API bool          Selectable(const char* label, bool* p_selected, const ImVec2& size = ImVec2(0,0));
*/
//IMGUI_API bool          ListBox(const char* label, int* current_item, const char** items, int items_count, int height_in_items = -1);
static int l_listbox(lua_State* L)
{
    const char *label = luaL_checkstring(L, 1);
    int current_item = luaL_checkinteger(L, 2);
    std::vector<const char*> items;
    luaL_checktype(L, 3, LUA_TTABLE);
    for (int i = 1;; i++)
    {
        lua_rawgeti(L, 3, i);
        if (lua_isnil(L, -1)){
            lua_pop(L, 1);
            break;
        }
        items.push_back(lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    int height_in_items = luaL_optinteger(L, 4, -1);
    bool ret = ImGui::ListBox(label, &current_item, items.data(), items.size(), height_in_items);
    lua_pushboolean(L,ret);
    lua_pushnumber(L,current_item);
    return 2;
}
/*
IMGUI_API bool          ListBox(const char* label, int* current_item, bool (*items_getter)(void* data, int idx, const char** out_text), void* data, int items_count, int height_in_items = -1);
IMGUI_API bool          ListBoxHeader(const char* label, const ImVec2& size = ImVec2(0,0)); // use if you want to reimplement ListBox() will custom data or interactions. make sure to call ListBoxFooter() afterwards.
IMGUI_API bool          ListBoxHeader(const char* label, int items_count, int height_in_items = -1); // "
IMGUI_API void          ListBoxFooter();                                                    // terminate the scrolling region

// Widgets: Value() Helpers. Output single value in "name: value" format (tip: freely declare your own within the ImGui namespace!)
IMGUI_API void          Value(const char* prefix, bool b);
IMGUI_API void          Value(const char* prefix, int v);
IMGUI_API void          Value(const char* prefix, unsigned int v);
IMGUI_API void          Value(const char* prefix, float v, const char* float_format = NULL);
IMGUI_API void          Color(const char* prefix, const ImVec4& v);
IMGUI_API void          Color(const char* prefix, unsigned int v);
*/
static int l_text(lua_State* L)
{
	size_t len;
    const char *str = luaL_checklstring(L, 1,&len);
	ImGui::TextUnformatted(str, str + len);
    return 0;
}
//IMGUI_API void          TextColored(const ImVec4& col, const char* fmt, ...);               // shortcut for PushStyleColor(ImGuiCol_Text, col); Text(fmt, ...); PopStyleColor();
//IMGUI_API void          TextWrapped(const char* fmt, ...);                                  // shortcut for PushTextWrapPos(0.0f); Text(fmt, ...); PopTextWrapPos();
//IMGUI_API void          TextUnformatted(const char* text, const char* text_end = NULL);     // doesn't require null terminated string if 'text_end' is specified. no copy done to any bounded stack buffer, recommended for long chunks of text
//IMGUI_API void          LabelText(const char* label, const char* fmt, ...);                 // display text+label aligned the same way as value+label widgets
static int l_bullet(lua_State* L)
{
    ImGui::Bullet();
    return 0;
}
static int l_bullet_text(lua_State* L)
{
    const char *str = luaL_checkstring(L, 1);
    ImGui::BulletText("%s",str);
    return 0;
}
static int l_button(lua_State* L)
{
    const char *str = luaL_checkstring(L, 1);
    ImVec2 size(0, 0);
    if (lua_gettop(L) > 1 && lua_istable(L,2))
    {
        get_size(L, 2, size);   
    }
    bool ret=ImGui::Button(str,size);
    lua_pushboolean(L, ret);
    return 1;
}
//IMGUI_API bool          SmallButton(const char* label);
//IMGUI_API bool          InvisibleButton(const char* str_id, const ImVec2& size);
//IMGUI_API void          Image(ImTextureID user_texture_id, const ImVec2& size, const ImVec2& uv0 = ImVec2(0,0), const ImVec2& uv1 = ImVec2(1,1), const ImVec4& tint_col = ImVec4(1,1,1,1), const ImVec4& border_col = ImVec4(0,0,0,0));
//IMGUI_API bool          ImageButton(ImTextureID user_texture_id, const ImVec2& size, const ImVec2& uv0 = ImVec2(0,0),  const ImVec2& uv1 = ImVec2(1,1), int frame_padding = -1, const ImVec4& bg_col = ImVec4(0,0,0,1), const ImVec4& tint_col = ImVec4(1,1,1,1));    // <0 frame_padding uses default frame padding settings. 0 for no padding
static int l_collapsing_header(lua_State*L)
{
    //TODO: display frame, default open
    const char *str = luaL_checkstring(L, 1);
    const char *str_id = luaL_optlstring(L, 2, NULL, NULL);
    bool ret=ImGui::CollapsingHeader(str,str_id = NULL);
    lua_pushboolean(L, ret);
    return 1;
}
static int l_checkbox(lua_State* L)
{
	const char *str = luaL_checkstring(L, 1);
	bool active = lua_toboolean(L, 2);

	bool ret = ImGui::Checkbox(str, &active);
	lua_pushboolean(L, ret);
	lua_pushboolean(L, active);
	return 2;
}
//IMGUI_API bool          Checkbox(const char* label, bool* v);
//IMGUI_API bool          CheckboxFlags(const char* label, unsigned int* flags, unsigned int flags_value);
static int l_radiobutton(lua_State* L)
{
    const char *str = luaL_checkstring(L, 1);
    bool active = lua_toboolean(L, 2);
        
    bool ret = ImGui::RadioButton(str, active);
    lua_pushboolean(L, ret);
    return 1;
}
//IMGUI_API bool          RadioButton(const char* label, int* v, int v_button); <<-- hard to expose?
static int l_combo(lua_State* L)
{
	const char *label = luaL_checkstring(L, 1);
	int current_item = luaL_checkinteger(L, 2);
	std::vector<const char*> items;
	luaL_checktype(L, 3, LUA_TTABLE);
	for (int i = 1;; i++)
	{
		lua_rawgeti(L, 3, i);
		if (lua_isnil(L, -1)) {
			lua_pop(L, 1);
			break;
		}
		items.push_back(lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	int height_in_items = luaL_optinteger(L, 4, -1);
	bool ret = ImGui::Combo(label, &current_item, items.data(), items.size(), height_in_items);
	lua_pushboolean(L, ret);
	lua_pushnumber(L, current_item);
	return 2;

}
//IMGUI_API bool          Combo(const char* label, int* current_item, const char** items, int items_count, int height_in_items = -1);
//IMGUI_API bool          Combo(const char* label, int* current_item, const char* items_separated_by_zeros, int height_in_items = -1);      // separate items with \0, end item-list with \0\0
//IMGUI_API bool          Combo(const char* label, int* current_item, bool(*items_getter)(void* data, int idx, const char** out_text), void* data, int items_count, int height_in_items = -1);
static int IMGUI_BEGIN_STATE = 0;
static int l_begin(lua_State* L)
{
    const char *str = "Debug";
    if (lua_isstring(L, 1))
    {
        str=lua_tostring(L, 1);
    }
    //TODO: flags here
    bool ret=ImGui::Begin(str);
    lua_pushboolean(L, ret);
	IMGUI_BEGIN_STATE++;
    return 1;
}
static int l_end(lua_State* L)
{
    ImGui::End();
	IMGUI_BEGIN_STATE--;
    return 0;
}
// Widgets: Sliders (tip: ctrl+click on a slider to input text)
static int l_slider_float(lua_State* L)
{
    const char *str = luaL_checkstring(L, 1);

    float v = lua_tonumber(L, 2);
    float v_min = lua_tonumber(L, 3);
    float v_max = lua_tonumber(L, 4);
    const char* display_format = luaL_optstring(L, 5, "%.3f");
    float power = luaL_optnumber(L, 6, 1.0f);
    bool ret = ImGui::SliderFloat(str, &v,v_min,v_max,display_format,power);
    lua_pushboolean(L, ret);
    lua_pushnumber(L, v);
    return 2;
}
//IMGUI_API bool          SliderFloat2(const char* label, float v[2], float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
//IMGUI_API bool          SliderFloat3(const char* label, float v[3], float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
//IMGUI_API bool          SliderFloat4(const char* label, float v[4], float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
static int l_slider_angle(lua_State* L)
{
    const char *str = luaL_checkstring(L, 1);

    float v = lua_tonumber(L, 2);
    float v_min = luaL_optnumber(L, 3, -360.0f);
    float v_max = luaL_optnumber(L, 4, +360.0f);
    bool ret = ImGui::SliderAngle(str, &v, v_min, v_max);
    lua_pushboolean(L, ret);
    lua_pushnumber(L, v);
    return 2;
}
static int l_slider_int(lua_State* L)
{
    const char *str = luaL_checkstring(L, 1);

    int v = lua_tointeger(L, 2);
    int v_min = lua_tointeger(L, 3);
    int v_max = lua_tointeger(L, 4);
    const char* display_format = luaL_optstring(L, 5, "%.0f");
    bool ret = ImGui::SliderInt(str, &v, v_min, v_max, display_format);
    lua_pushboolean(L, ret);
    lua_pushinteger(L, v);
    return 2;
}
//IMGUI_API bool          SliderInt2(const char* label, int v[2], int v_min, int v_max, const char* display_format = "%.0f");
//IMGUI_API bool          SliderInt3(const char* label, int v[3], int v_min, int v_max, const char* display_format = "%.0f");
//IMGUI_API bool          SliderInt4(const char* label, int v[4], int v_min, int v_max, const char* display_format = "%.0f");
//IMGUI_API bool          VSliderFloat(const char* label, const ImVec2& size, float* v, float v_min, float v_max, const char* display_format = "%.3f", float power = 1.0f);
//IMGUI_API bool          VSliderInt(const char* label, const ImVec2& size, int* v, int v_min, int v_max, const char* display_format = "%.0f");
static int l_same_line(lua_State* L)
{
    int x = luaL_optinteger(L, 1, 0);
    int w = luaL_optinteger(L, 2, -1);
    ImGui::SameLine(x, w);
    return 0;
}
static const luaL_Reg lua_imgui[] = {
    { "Begin", l_begin },
    { "End", l_end },
    { "Text", l_text },
    { "Bullet", l_bullet },
    { "BulletText", l_bullet_text },
    { "Button", l_button },
    { "RadioButton", l_radiobutton },
	{ "Checkbox", l_checkbox },
    { "CollapsingHeader", l_collapsing_header },
    { "SliderFloat", l_slider_float },
    { "SliderAngle", l_slider_angle },
    { "SliderInt", l_slider_int },
    { "PlotLines", l_plot_lines },
    { "InputText",l_input_text },
    { "ListBox", l_listbox },
	{ "Combo", l_combo },
    { "ColorEdit3", l_color_edit3 },
    { "ColorEdit4", l_color_edit4 },
    { "ColorButton", l_color_button },
    { "SameLine",l_same_line },
    { NULL, NULL }
};

int lua_open_imgui(lua_State* L)
{
    luaL_newlib(L, lua_imgui);

    lua_setglobal(L, "imgui");

    return 1;
}

void fixup_imgui_state()
{
	for(int i=0;i<IMGUI_BEGIN_STATE;i++)
	{
		ImGui::End();
	}
	IMGUI_BEGIN_STATE = 0;
}
