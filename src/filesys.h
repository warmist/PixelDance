#pragma once

#include <string>
#include <vector>

std::vector<std::string> enum_files(const std::string& path);

struct dir_watcher
{
    void* change_handle;

    dir_watcher(const std::string& path);
    ~dir_watcher();

    dir_watcher(const dir_watcher& other) = delete;
    dir_watcher& operator=(const dir_watcher& other) = delete;

    bool check_changes();
};
struct file_time
{
    unsigned long low;
    unsigned long high;
};
struct watched_file
{
    std::string path;
    std::string unprefixed_path;
    file_time last_access;
    bool exists=false;
    bool changed=false;
};
struct file_watcher
{
    std::vector<watched_file> files;

    bool check_changes();
};