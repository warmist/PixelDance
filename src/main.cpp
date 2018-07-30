
#include "lua.hpp"
#include "imgui.h"
#include "imgui-SFML.h"

#include "SFML\Graphics.hpp"

int main(int argc, char** argv)
{
	sf::RenderWindow window(sf::VideoMode(640, 480), "ImGui + SFML = <3");
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

		ImGui::SFML::Update(window, deltaClock.restart());

		ImGui::ShowDemoWindow();

		ImGui::Begin("Hello, world!");
		ImGui::Button("Look at this pretty button");
		ImGui::End();

		window.clear();
		ImGui::SFML::Render(window);
		window.display();
	}

	ImGui::SFML::Shutdown();

	return 0;
}