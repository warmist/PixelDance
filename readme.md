# PixelDance

This is a program for various pixel toys. It currently has luajit for pixel operations and opengl for various shader play.

## Features

* Luajit engine for easy and fast scripting
* Auto file reload on modification for very easy use - just have pixel dance and text editor open and see how you changes change the view
* Opengl for shader-based rendering
* Easy modification with c-like source
* Imgui that is exposed to lua for easy gui creation and even faster iteration

## Use

Run `pixeldance.exe <path to project folder>` and select lua project from dropdown.

## Projects

Stuff in projects folder is everchanging mess of lua that does all the magic. things that end in `.llib` is not auto-loaded and displayed in dropdown but can be `required` by lua - thus lua-libs.

Some old stuff is not working or not-recommended way of doing stuff but mostly updated and played with are:

* ecology series - a small ecology sims
* slimemold - slime mold sim inspired by [this page](https://sagejenson.com/physarum)
* crystals - an interpretation of [this page](http://mkweb.bcgsc.ca/snowflakes/letitsnow.mhtml) but a very loose one
* IFS_shader - a fractal/fractal flame generator

## Build

Get `SFML`, `luajit`, `DearImgui`, `Cmake` and your favorite compiler. Modify `CMake` to point to libs, make, build and enjoy.

Currently only windows are supported but pull-req are welcome.

## License

This software is released under `CC-BY: Attribution` license. More about it [here](https://creativecommons.org/licenses/by/4.0/)