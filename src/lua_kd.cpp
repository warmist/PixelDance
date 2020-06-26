#include "lua_kd.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

#include "nanoflann.hpp"
//TODO: ADD GC!!
using namespace nanoflann;

template <typename T>
struct PointCloud3d
{
    struct Point
    {
        T  x, y, z;
    };

    std::vector<Point>  pts;

    // Must return the number of data points
    inline size_t kdtree_get_point_count() const { return pts.size(); }

    // Returns the dim'th component of the idx'th point in the class:
    // Since this is inlined and the "dim" argument is typically an immediate value, the
    //  "if/else's" are actually solved at compile time.
    inline T kdtree_get_pt(const size_t idx, const size_t dim) const
    {
        if (dim == 0) return pts[idx].x;
        else if (dim == 1) return pts[idx].y;
        else return pts[idx].z;
    }

    // Optional bounding-box computation: return false to default to a standard bbox computation loop.
    //   Return true if the BBOX was already computed by the class and returned in "bb" so it can be avoided to redo it again.
    //   Look at bb.size() to find out the expected dimensionality (e.g. 2 or 3 for point clouds)
    template <class BBOX>
    bool kdtree_get_bbox(BBOX& /* bb */) const { return false; }

};

template <typename T>
struct PointCloud2d
{
    struct Point
    {
        T  x, y;
    };

    std::vector<Point>  pts;

    // Must return the number of data points
    inline size_t kdtree_get_point_count() const { return pts.size(); }

    // Returns the dim'th component of the idx'th point in the class:
    // Since this is inlined and the "dim" argument is typically an immediate value, the
    //  "if/else's" are actually solved at compile time.
    inline T kdtree_get_pt(const size_t idx, const size_t dim) const
    {
        if (dim == 0) return pts[idx].x;
        else return pts[idx].y;
    }

    // Optional bounding-box computation: return false to default to a standard bbox computation loop.
    //   Return true if the BBOX was already computed by the class and returned in "bb" so it can be avoided to redo it again.
    //   Look at bb.size() to find out the expected dimensionality (e.g. 2 or 3 for point clouds)
    template <class BBOX>
    bool kdtree_get_bbox(BBOX& /* bb */) const { return false; }

};

typedef KDTreeSingleIndexDynamicAdaptor<
    L2_Simple_Adaptor<float, PointCloud3d<float> >,
    PointCloud3d<float>,
    3 /* dim */
> kd_3d_t;

typedef KDTreeSingleIndexDynamicAdaptor<
    L2_Simple_Adaptor<float, PointCloud2d<float> >,
    PointCloud2d<float>,
    2 /* dim */
> kd_2d_t;

struct l_kd_3d_t
{
    PointCloud3d<float> cloud;
    kd_3d_t tree;
    l_kd_3d_t():tree(3,cloud) {}
};

static l_kd_3d_t* check3(lua_State* L, int id) { return reinterpret_cast<l_kd_3d_t*>(luaL_checkudata(L, id, "kd_3d")); }


struct l_kd_2d_t
{
    PointCloud2d<float> cloud;
    kd_2d_t tree;
    l_kd_2d_t() :tree(2, cloud) {}
};

static l_kd_2d_t* check2(lua_State* L, int id) { return reinterpret_cast<l_kd_2d_t*>(luaL_checkudata(L, id, "kd_2d")); }
void get_point3(lua_State* L, int idx,float& x,float& y,float& z)
{
    lua_rawgeti(L, idx, 1);
    x = lua_tonumber(L, -1);
    lua_rawgeti(L, idx, 2);
    y = lua_tonumber(L, -1);
    lua_rawgeti(L, idx, 3);
    z = lua_tonumber(L, -1);
}
static int add_point3(lua_State* L)
{
    auto p=check3(L, 1);
    //todo: add multiple points
    if (lua_istable(L, 2))
    {
        float x, y, z;
        get_point3(L, -1, x, y, z);
        p->cloud.pts.emplace_back(PointCloud3d<float>::Point{ x, y, z });
        auto pid = p->cloud.pts.size() - 1;
        p->tree.addPoints(pid,pid);
    }
    else
    {
        luaL_error(L, "exptected table");
    }
    return 0;
}
static int knn_lookup3(lua_State* L)
{
    auto p = check3(L, 1);
    int num = luaL_checkint(L, 2);
    float f[3];
    get_point3(L, 3, f[0], f[1], f[2]);
    KNNResultSet<float> rez(num);
    
    std::vector<size_t> indexes;
    std::vector<float> distances;
    rez.init(indexes.data(), distances.data());
    bool full=p->tree.findNeighbors(rez, f,SearchParams(10));
    lua_newtable(L);
    for(int i=0;i<rez.size();i++)
    {
        lua_newtable(L);
        lua_pushinteger(L, indexes[i]);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, distances[i]);
        lua_rawseti(L, -2, 2);

        lua_rawseti(L, -2, i+1);
    }
    return 1;
}
static int dist_lookup3(lua_State* L)
{
    auto p = check3(L, 1);
    float radius = luaL_checknumber(L, 2);
    float f[3];
    get_point3(L, 3, f[0], f[1], f[2]);
    std::vector<std::pair<size_t,float>> rez_vec;
    RadiusResultSet<float> rez(radius, rez_vec);
    rez.init();

    bool full = p->tree.findNeighbors(rez, f, SearchParams(10));
    lua_newtable(L);
    for (int i = 0; i < rez_vec.size(); i++)
    {
        lua_newtable(L);
        lua_pushinteger(L, rez_vec[i].first);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, rez_vec[i].second);
        lua_rawseti(L, -2, 2);

        lua_rawseti(L, -2, i+1);
    }
    return 1;
}
static int make_tree3(lua_State* L) {
    auto np = lua_newuserdata(L, sizeof(l_kd_3d_t));
    new(np) l_kd_3d_t;
    auto ret = reinterpret_cast<l_kd_3d_t*>(np);

    if (luaL_newmetatable(L, "kd_3d"))
    {
        lua_pushcfunction(L, add_point3);
        lua_setfield(L, -2, "add");

        lua_pushcfunction(L, knn_lookup3);
        lua_setfield(L, -2, "knn");

        lua_pushcfunction(L, dist_lookup3);
        lua_setfield(L, -2, "rnn");

        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    return 1;
}
void get_point2(lua_State* L, int idx, float& x, float& y)
{
    lua_rawgeti(L, idx, 1);
    x = lua_tonumber(L, -1);
    lua_rawgeti(L, idx, 2);
    y = lua_tonumber(L, -1);
}
static int add_point2(lua_State* L)
{
    auto p = check2(L, 1);
    //todo: add multiple points
    if (lua_istable(L, 2))
    {
        float x, y;
        get_point2(L, 2, x, y);
        p->cloud.pts.emplace_back(PointCloud2d<float>::Point{ x, y });
        auto pid = p->cloud.pts.size() - 1;
        p->tree.addPoints(pid, pid);
    }
    else
    {
        luaL_error(L, "exptected table");
    }
    return 0;
}
static int knn_lookup2(lua_State* L)
{
    auto p = check2(L, 1);
    int num = luaL_checkint(L, 2);
    float f[2];
    get_point2(L, 3, f[0], f[1]);
    KNNResultSet<float> rez(num);

    std::vector<size_t> indexes;
    indexes.resize(num);
    std::vector<float> distances;
    distances.resize(num);
    rez.init(indexes.data(), distances.data());
    bool full = p->tree.findNeighbors(rez, f, SearchParams(10));
    lua_newtable(L);
    for (int i = 0; i < rez.size(); i++)
    {
        lua_newtable(L);
        lua_pushinteger(L, indexes[i]);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, distances[i]);
        lua_rawseti(L, -2, 2);

        lua_rawseti(L, -2, i+1);
    }
    return 1;
}
static int dist_lookup2(lua_State* L)
{
    auto p = check2(L, 1);
    float radius = luaL_checknumber(L, 2);
    float f[2];
    get_point2(L, 3, f[0], f[1]);
    std::vector<std::pair<size_t, float>> rez_vec;
    RadiusResultSet<float> rez(radius, rez_vec);
    rez.init();

    bool full = p->tree.findNeighbors(rez, f, SearchParams(10));
    lua_newtable(L);
    for (int i = 0; i < rez_vec.size(); i++)
    {
        lua_newtable(L);
        lua_pushinteger(L, rez_vec[i].first);
        lua_rawseti(L, -2, 1);
        lua_pushnumber(L, rez_vec[i].second);
        lua_rawseti(L, -2, 2);

        lua_rawseti(L, -2, i+1);
    }
    return 1;
}
static int make_tree2(lua_State* L) {
    auto np = lua_newuserdata(L, sizeof(l_kd_2d_t));
    new(np) l_kd_2d_t;
    auto ret = reinterpret_cast<l_kd_2d_t*>(np);

    if (luaL_newmetatable(L, "kd_2d"))
    {
        lua_pushcfunction(L, add_point2);
        lua_setfield(L, -2, "add");

        lua_pushcfunction(L, knn_lookup2);
        lua_setfield(L, -2, "knn");

        lua_pushcfunction(L, dist_lookup2);
        lua_setfield(L, -2, "rnn");

        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    return 1;
}
static int make_tree(lua_State* L) {
    int dim=luaL_checkint(L, 1);
    if (dim == 2)
        return make_tree2(L);
    if(dim==3)
        return make_tree3(L);
    luaL_error(L, "Unsupported number of dimensions (%d), was expecting 2 or 3", dim);
    return 0;
    
}

static const luaL_Reg lua_kd_lib[] = {
    { "Make",make_tree },
    { NULL, NULL }
};
int lua_open_kd(lua_State * L)
{
    luaL_newlib(L, lua_kd_lib);
    lua_setglobal(L, "kd_tree");

    return 1;
}