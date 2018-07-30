#include "lua.hpp"
#include "imgui.h"
#include "imgui-SFML.h"

#include "SFML\Graphics.hpp"

#include "filesys.h"

int main(int argc, char** argv)
{
    if (argc == 1)
    {
        printf("Usage: pixeldance.exe <path-to-projects>\n");
        return -1;
    }
    std::string path_prefix = argv[1];
    file_watcher fwatch;
    auto pfiles=enum_files( path_prefix + "/*.lua");
    for (auto p : pfiles)
    {
        //TODO: add to project list
        watched_file f;
        f.path = path_prefix+"/"+p;
        fwatch.files.emplace_back(f);
    }

    sf::RenderWindow window(sf::VideoMode(1024, 1024), "PixelDance");
    window.setFramerateLimit(60);
    ImGui::SFML::Init(window);

    sf::Clock deltaClock;
    while (window.isOpen()) {
        sf::Event event;
        while (window.pollEvent(event)) {
            ImGui::SFML::ProcessEvent(event);

            if (event.type == sf::Event::Closed) {
                window.close();
            }
        }
        if (fwatch.check_changes())
        {
            for (auto& f : fwatch.files)
            {
                if (f.changed)
                {
                    //TODO: use changes
                }
            }
        }
        ImGui::SFML::Update(window, deltaClock.restart());

        //ImGui::ShowDemoWindow();
        ImGui::Begin("Projects");
        if(ImGui::BeginCombo("Current project", "<no project>"))
        {
            for (auto& f : fwatch.files)
            {
                bool t = false;
                ImGui::Selectable(f.path.c_str(), &t);
            }
            
            
            ImGui::EndCombo();
        }
        ImGui::End();


        window.clear();
        ImGui::SFML::Render(window);
        window.display();
    }

    ImGui::SFML::Shutdown();

    return 0;
}