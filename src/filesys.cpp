#include "filesys.h"

#include <windows.h>
#include <tchar.h>
#include <stdio.h>



std::vector<std::string> enum_files(const std::string& path)
{
    WIN32_FIND_DATA FindFileData;
    HANDLE hFind;

    std::vector<std::string> ret;
    hFind = FindFirstFile(path.c_str(), &FindFileData);
    if (hFind == INVALID_HANDLE_VALUE)
    {
        return ret;
    }
    else
    {
        while (hFind)
        {
            ret.push_back(FindFileData.cFileName);
            if (!FindNextFile(hFind, &FindFileData))
                break;
        }
    }
    FindClose(hFind);
    return ret;
}

dir_watcher::dir_watcher(const std::string& path)
{
    change_handle = FindFirstChangeNotification(path.c_str(), false, FILE_NOTIFY_CHANGE_CREATION | FILE_NOTIFY_CHANGE_LAST_WRITE);
}
dir_watcher::~dir_watcher()
{
    FindCloseChangeNotification(change_handle);
}

bool dir_watcher::check_changes()
{
    unsigned long  stat = WaitForSingleObject(change_handle, 0);
    if (stat == WAIT_TIMEOUT)
    {
        return false;
    }
    if (FindNextChangeNotification(change_handle) == FALSE)
    {
        throw std::runtime_error("Find next change failed");
    }
    return true;
}

static_assert(sizeof(FILETIME) == sizeof(file_time),"File time struct must match windows struct");

bool file_watcher::check_changes()
{
    bool any_changed = false;
    for (auto& f : files)
    {
        WIN32_FILE_ATTRIBUTE_DATA attribs;
        if (GetFileAttributesEx(f.path.c_str(), GetFileExInfoStandard, &attribs) == 0)
        {
            f.exists = false;
            continue;
        }
        f.exists = true;
        auto nlow = attribs.ftLastWriteTime.dwLowDateTime;
        auto nhigh = attribs.ftLastWriteTime.dwHighDateTime;
        if (nlow != f.last_access.low || nhigh != f.last_access.high)
        {
            f.changed = true;
            any_changed = true;
        }
        else
            f.changed = false;
        f.last_access = file_time{  nlow,nhigh  };
    }
    return any_changed;
}
