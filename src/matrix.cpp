#include "matrix.h"

#include "lua.hpp"
#include "lualib.h"
#include "lauxlib.h"

#include <vector>
struct mini_mat
{
    int w, h;
    float* data;
    bool owned = false;
    mini_mat() {}
    mini_mat(int w, int h) :w(w), h(h), data(new float[w*h]), owned(true) {}
    mini_mat(int w, int h,float *data) :w(w), h(h), data(data), owned(false) {}
    ~mini_mat()
    {
        if (owned)
            delete[] data;
    }
    float& operator()(int x, int y) {
        //maybe check bounds?
        return data[x + y * w];
    }
    const float& operator()(int x, int y) const {
        //maybe check bounds?
        return data[x + y * w];
    }
    void mult(const mini_mat& m2, mini_mat& m3)
    {
        auto& m1 = (*this);
        for (int x = 0; x < m2.w; ++x)
            for (int y = 0; y < m1.h; ++y)
            {
                float& f = m3(x, y);
                f = 0;
                for (int k = 0; k < m1.w; ++k)
                    f += m1(k, y)*m2(x, k);
            }
    }
};
static mini_mat check(lua_State* L, int id,int force_w=0,int force_h=0) {
    luaL_checktype(L, id, LUA_TTABLE);
    lua_getfield(L, id, "d");
    if (lua_type(L, -1) != 10 /*cdata*/ && (lua_type(L, -1) != LUA_TLIGHTUSERDATA))
    {
        luaL_error(L, "bad argument %d, expected table with '.d' pointer", id);
    }
    float* mat=(float*)lua_topointer(L, -1);

    lua_pop(L, 1);
    lua_getfield(L, id, "w");
    if(!lua_isnumber(L,-1))
        luaL_error(L, "bad argument %d, expected table with '.w' size", id);
    int w = lua_tointeger(L, -1);
    if (force_w != 0 && force_w != w)
        luaL_error(L, "bad argument %d, matrix w is wrong (expected %d)", id, force_w);
    lua_pop(L, 1);

    lua_getfield(L, id, "h");
    if (!lua_isnumber(L, -1))
        luaL_error(L, "bad argument %d, expected table with '.h' size", id);
    int h = lua_tointeger(L, -1);
    if (force_h != 0 && force_h != h)
        luaL_error(L, "bad argument %d, matrix h is wrong (expected %d)", id,force_h);
    lua_pop(L, 1);

    lua_getfield(L, id, "type");
    if (!lua_isnumber(L, -1) || lua_tointeger(L,-1) != 2)
        luaL_error(L, "bad argument %d, expected table with '.type==2' (i.e. only float mat)", id);

    lua_pop(L, 1);
    return mini_mat{ w,h,mat};
}
//all of this is not "creating" new matrixes, so needs output too
static int mult_lua_matrix(lua_State* L)
{
    //in NxM and MxL output NxL matrix
    
    auto m1 = check(L, 1, 0, 0);
    
    auto m2 = check(L, 2, 0, m1.w);
    if (m1.h == 1 && m2.w == 1 && lua_gettop(L)==2)
    {
        //special case, one number only
        float f = 0;
        for (int k = 0; k < m1.w; ++k)
            f += m1(k, 0)*m2(0, k);
        lua_pushnumber(L, f);
        return 1;
    }
    auto m3 = check(L, 3, m2.w, m1.h);
    //matrix multiplication

    m1.mult(m2, m3);
    return 0;
}
static int transpose_lua_matrix(lua_State* L)
{
    //in NxM and output MxN matrix
    auto m1 = check(L, 1);
    auto m2 = check(L, 2, m1.h, m1.w);
    for (int x = 0; x < m1.w; ++x)
        for (int y = 0; y < m1.h; ++y)
        {
            m2(y, x) = m1(x, y);
        }
    return 0;
}
std::vector<float> scratch;
static int solve_qr_lua_matrix(lua_State* L)
{
    auto A = check(L, 1);
    auto B = check(L, 2, 1, A.h);
    //Ax=B => A=QR
    //then https://en.wikipedia.org/wiki/QR_decomposition#Using_for_solution_to_linear_inverse_problems
    //and done...
    return 0;
}
static const luaL_Reg lua_matrix_lib[] = {
    { "mult",mult_lua_matrix },
    { "transpose",transpose_lua_matrix },
    { "solve_by_qr",solve_qr_lua_matrix },
    { NULL, NULL }
};

int lua_open_matrix(lua_State * L)
{
    luaL_newlib(L, lua_matrix_lib);

    lua_setglobal(L, "matrix");

    return 1;
}
