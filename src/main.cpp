#include "lua.hpp"
#include "imgui.h"
#include "imgui-SFML.h"

#include "SFML\Graphics.hpp"

#include "filesys.h"
#include "limgui.h"
#include "lua_buffers.h"
#include "stb_image.h"
#include "stb_image_write.h"
#define WRAP_CPP_EXCEPTIONS

#include "SFML\OpenGL.hpp"

#define GL_LITE_IMPLEMENTATION
#include "gl_lite.h"

#include "shaders.h"
void load_projects(const char* prefix,file_watcher& fwatch)
{
    std::string path_prefix = prefix;
    auto pfiles = enum_files(path_prefix + "/*.lua");
    for (auto p : pfiles)
    {
        //TODO: add to project list
        watched_file f;
        f.path = path_prefix + "/" + p;
        fwatch.files.emplace_back(f);
    }
}
static int wrap_exceptions(lua_State *L, lua_CFunction f)
{
	try {
		return f(L);  // Call wrapped function and return result.
	}
	catch (const char *s) {  // Catch and convert exceptions.
		lua_pushstring(L, s);
	}
	catch (std::exception& e) {
		lua_pushstring(L, e.what());
	}
	catch (...) {
		lua_pushliteral(L, "caught (...)");
	}
	return lua_error(L);  // Rethrow as a Lua error.
}
static int msghandler(lua_State *L) {
	const char *msg = lua_tostring(L, 1);
	if (msg == NULL) {  /* is error object not a string? */
		if (luaL_callmeta(L, 1, "__tostring") &&  /* does it have a metamethod */
			lua_type(L, -1) == LUA_TSTRING)  /* that produces a string? */
			return 1;  /* that is the message */
		else
			msg = lua_pushfstring(L, "(error object is a %s value)",
				luaL_typename(L, 1));
	}
	luaL_traceback(L, L, msg, 1);  /* append a standard traceback */
	return 1;  /* return the traceback */
}

static int docall(lua_State *L, int narg, int nres) {
	int status;
	int base = lua_gettop(L) - narg;  /* function index */
	lua_pushcfunction(L, msghandler);  /* push message handler */
	lua_insert(L, base);  /* put it under function and args */
	status = lua_pcall(L, narg, nres, base);
	lua_remove(L, base);  /* remove message handler from the stack */
	return status;
}
static int lua_read_only(lua_State* L)
{
	luaL_error(L,"Tried to write to read-only table");
	return 0;
}
static int present_buffer(lua_State* L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    /*lua_getfield(L, 1, "w");
    lua_getfield(L, 1, "h");*/

    lua_getfield(L, 1, "d");
    auto data=reinterpret_cast<const sf::Uint8*>(lua_topointer(L, -1));
    lua_pop(L, 1);
    
    lua_getglobal(L, "STATE");
    lua_getfield(L, -1, "texture");

    auto tex = reinterpret_cast<sf::Texture*>(lua_touserdata(L, -1));
    lua_pop(L, 2);
    tex->update(data);
    return 0;
}
static int save_image(lua_State* L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "w");
    int w=lua_tonumber(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, 1, "h");
    int h = lua_tonumber(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, 1, "d");
    auto data = reinterpret_cast<const sf::Uint8*>(lua_topointer(L, -1));
    lua_pop(L, 1);

    const char* path = luaL_checkstring(L, 2);
    size_t suffix_len = 0;
    const char* suffix = luaL_optlstring(L, 3, "", &suffix_len);


    auto ret = stbi_write_png(path, w, h, 4, data, w * 4);
    if (suffix_len != 0)
    {
        auto f = fopen(path, "ab");
        fwrite(suffix, suffix_len, 1, f);
        fclose(f);
        //later this will be better, now need to update to sfml2.5
        /*int out_len;
        auto f = fopen(path, "wb");
        ret= stbi_write_png_to_func(&fwrite_callback,f, e.w, ptr->size() / e.w, 4, ptr->data(), e.w * 4);
        fwrite(suffix, suffix_len, 1, f);
        fclose(f);*/
    }
    lua_pushinteger(L, ret);
    return 1;
}
struct lua_global_state
{
	sf::Vector2u size;
	sf::Texture* tex;
	void write(lua_State* L)
	{
		if (!L)
			return;
		lua_newtable(L);

		lua_newtable(L);
		lua_pushinteger(L, size.x);
		lua_rawseti(L, -2, 1);
		lua_pushinteger(L, size.y);
		lua_rawseti(L, -2, 2);

		lua_setfield(L, -2, "size");

		lua_pushlightuserdata(L, tex);
		lua_setfield(L, -2, "texture");

		
		lua_newtable(L);

		lua_pushvalue(L, -2);
		lua_setfield(L, -2, "__index");

		lua_pushcfunction(L, lua_read_only);
		lua_setfield(L, -2, "__newindex");

		lua_pushboolean(L, false);
		lua_setfield(L, -2, "__metatable");

		lua_setmetatable(L, -2);

		lua_setglobal(L, "STATE");
	}
};
int setLuaPath(lua_State* L, const char* path)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "path"); // get field "path" from table at top of stack (-1)
	std::string cur_path = lua_tostring(L, -1); // grab path string from top of stack
	cur_path.append(";"); // do your path magic here
	cur_path.append(path);
	lua_pop(L, 1); // get rid of the string on the stack we just pushed on line 5
	lua_pushstring(L, cur_path.c_str()); // push the new one
	lua_setfield(L, -2, "path"); // set the field "path" in table at -2 with value at top of stack
	lua_pop(L, 1); // get rid of package table from top of stack
	return 0; // all done!
}
static int lua_get_my_source(lua_State* L);
struct project {
    lua_State *L=nullptr;
    std::string path;
    std::vector<std::string> errors;
	bool is_errored = false;
	lua_global_state state;

    project() {}
    ~project() { if(L)lua_close(L); };

    void init_lua() {
        if (L)
            lua_close(L);
        L = luaL_newstate();
        luaL_openlibs(L);
		setLuaPath(L, ".\\libs\\?.lua");
		lua_open_imgui(L);
		lua_open_buffers(L);
		lua_open_shaders(L);
#ifdef WRAP_CPP_EXCEPTIONS
		lua_pushlightuserdata(L, (void *)wrap_exceptions);
		luaJIT_setmode(L, -1, LUAJIT_MODE_WRAPCFUNC | LUAJIT_MODE_ON);
		lua_pop(L, 1);
#endif
		lua_pushlightuserdata(L, this);
		lua_setglobal(L, "__project");

		lua_pushcfunction(L, lua_get_my_source);
		lua_setglobal(L, "__get_source");

        lua_pushcfunction(L, present_buffer);
        lua_setglobal(L, "__present");

        lua_pushcfunction(L, save_image);
        lua_setglobal(L, "__save_png");

		state.write(L);
    }
    void reload_file()
    {
		if (path == "")
		{
			is_errored = true;
			return;
		}
        if (luaL_dofile(L, path.c_str()) != 0)
        {
            size_t len;
            const char* err=lua_tolstring(L, 1, &len);
            std::string error_str(err, len);
            errors.push_back(error_str);
			is_errored = true;
        }
		else
			is_errored = false;
    }
    void load_file(std::string file_path)
    {
        path = file_path;
        reload_file();
    }
    void clear_errors()
    {
        errors.clear();
		is_errored = false;
    }
    void reset()
    {
        clear_errors();
        init_lua();
        reload_file();
    }
	void set_mouse()
	{
		auto& io = ImGui::GetIO();
		lua_newtable(L);

		lua_pushnumber(L, io.MousePos.x);
		lua_setfield(L, -2, "x");

		lua_pushnumber(L, io.MousePos.y);
		lua_setfield(L, -2, "y");
		
#define ADD_MOUSE(x) lua_pushboolean(L, io.MouseDownOwned[x]); lua_setfield(L, -2, "owned" ## # x); lua_pushboolean(L, io.MouseClicked[x]); lua_setfield(L, -2, "clicked" ## # x); lua_pushboolean(L, io.MouseReleased[x]); lua_setfield(L, -2, "released" ## # x)
		ADD_MOUSE(0);
		ADD_MOUSE(1);
		ADD_MOUSE(2);
		ADD_MOUSE(3);
		ADD_MOUSE(4);
#undef ADD_MOUSE
		lua_setfield(L, LUA_GLOBALSINDEX, "__mouse");
	}
	void update()
	{
		if (is_errored)
			return;
		lua_getglobal(L, "update");
		if (!lua_isnil(L, -1))
		{
			if (docall(L, 0, 0))
			{
				is_errored = true;
				errors.emplace_back(lua_tostring(L, -1));
			}
		}
		else
		{
			lua_pop(L, 1);
		}
		fixup_imgui_state();
	}
    void resize(int w,int h)
    {
        if (is_errored)
            return;
        lua_getglobal(L, "resize");
        if (!lua_isnil(L, -1))
        {
            lua_pushnumber(L,w);
            lua_pushnumber(L,h);
            if (docall(L, 2, 0))
            {
                is_errored = true;
                errors.emplace_back(lua_tostring(L, -1));
            }
        }
        else
        {
            lua_pop(L, 1);
        }
        fixup_imgui_state();
    }
	void load_image(const char* path)
	{
		auto f=fopen(path, "rb");
		int x, y, comp;

		auto data = stbi_load_from_file(f, &x, &y, &comp, 4);
		stbi_image_free(data);
		auto pos = ftell(f);
		fseek(f, 0, SEEK_END);
		auto size = ftell(f);
		std::vector<unsigned char> buffer;
		buffer.resize(size - pos);
		fseek(f, pos, SEEK_SET);
		fread(buffer.data(), size - pos, 1, f);
		fclose(f);
	}
};
static int lua_get_my_source(lua_State* L)
{
	lua_getglobal(L, "__project");
	auto p = reinterpret_cast<project*>(lua_touserdata(L, -1));
	lua_pop(L, 1);

	auto f=fopen(p->path.c_str(), "rb");
	fseek(f, 0, SEEK_END);
	auto size = ftell(f);
	fseek(f, 0, SEEK_SET);
	std::vector<unsigned char> buffer;
	buffer.resize(size);
	fread(buffer.data(), size, 1, f);
	fclose(f);

	lua_pushlstring(L, (const char*)buffer.data(), buffer.size());
	return 1;
}
int main(int argc, char** argv)
{
    if (argc == 1)
    {
        printf("Usage: pixeldance.exe <path-to-projects>\n");
        return -1;
    }
	
    file_watcher fwatch;
    load_projects(argv[1], fwatch);
	sf::ContextSettings settings;
	settings.depthBits = 24;
	settings.stencilBits = 8;
	settings.antialiasingLevel = 4;
	/*settings.majorVersion = 3;
	settings.minorVersion = 0;
	settings.attributeFlags = sf::ContextSettings::Attribute::Core;*/
	//settings.sRgbCapable = true;
    sf::RenderWindow window(sf::VideoMode(1024, 1024), "PixelDance",sf::Style::Default,settings);
    window.setFramerateLimit(60);
    ImGui::SFML::Init(window);
	
	if (!gl_lite_init())
	{
		printf("Failed to init gl_lite");
		return -1;
	}

	auto csize = window.getSize();

	sf::Texture back_buffer;

	back_buffer.create(csize.x, csize.y);
	
	sf::Sprite back_buffer_sprite;
	back_buffer_sprite.setTexture(back_buffer,true);

    project current_project;
	current_project.state = { csize ,&back_buffer};
    current_project.init_lua();
	
    int selected_project = -1;
    int old_selected = selected_project;
    sf::Clock deltaClock;
    while (window.isOpen()) {
        sf::Event event;
        while (window.pollEvent(event)) {
            ImGui::SFML::ProcessEvent(event);

            if (event.type == sf::Event::Closed) {
                window.close();
            }
			if (event.type == sf::Event::Resized)
			{
				auto ev = event.size;
				//sf::Texture new_texture;
				//new_texture
				back_buffer.create(ev.width, ev.height);
				back_buffer_sprite.setTextureRect(sf::IntRect(0, 0, ev.width, ev.height));
				current_project.state = { sf::Vector2u(ev.width,ev.height),&back_buffer };
				current_project.state.write(current_project.L);
				resize_lua_buffers(ev.width, ev.height);
				window.setView(sf::View(sf::Vector2f(ev.width / 2, ev.height / 2), sf::Vector2f(ev.width, ev.height)));
                current_project.resize(ev.width, ev.height);
			}
        }
		bool need_reload = false;
        if (fwatch.check_changes())
        {
            for (auto& f : fwatch.files)
            {
                if (f.changed && f.exists)
                {
                    //TODO: use changes
					if (current_project.path == f.path)
					{
						need_reload = true;
					}
                }
            }
        }
        ImGui::SFML::Update(window, deltaClock.restart());

		if(need_reload)
			current_project.reload_file();
		current_project.set_mouse();
		
		current_project.update();

        ImGui::Begin("Projects");
		ImGui::Text("FPS:%g", ImGui::GetIO().Framerate);
        const char* project_name = "<no project>";
        if (selected_project >= 0 && selected_project < fwatch.files.size())
            project_name = fwatch.files[selected_project].path.c_str();

        if(ImGui::BeginCombo("Current project", project_name))
        {
            bool t = (selected_project==-1);
            ImGui::Selectable("<no project>", &t);
            if (t)
                selected_project = -1;
            int k = 0;
            for (auto& f : fwatch.files)
            {
                t = (selected_project == k);
                if(ImGui::Selectable(f.path.c_str(), &t))
                    selected_project = k;
                k++;
            }
            ImGui::EndCombo();
        }
        if (old_selected != selected_project)
        {
            if(selected_project!=-1)
            {
                current_project.load_file(fwatch.files[selected_project].path);
            }
			else
			{
				current_project.load_file("");
			}
        }
        old_selected = selected_project;
        ImGui::Separator();
        if (ImGui::Button("Clear"))
            current_project.clear_errors();

        ImGui::SameLine();
        if (ImGui::Button("Reset"))
            current_project.reset();

        ImGui::BeginChild("ScrollingRegion", ImVec2(0, 0), true, ImGuiWindowFlags_HorizontalScrollbar);
        for (auto& s : current_project.errors)
            ImGui::Text("%s", s.c_str());
        ImGui::EndChild();
        ImGui::End();


        window.clear();
		window.draw(back_buffer_sprite);
        ImGui::SFML::Render(window);
        window.display();
    }
    
    ImGui::SFML::Shutdown();

    return 0;
}