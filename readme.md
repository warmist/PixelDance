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

## Build

Get `SFML`, `luajit`, `DearImgui`, `Cmake` and your favorite compiler. Modify `CMake` to point to libs, make, build and enjoy.

Currently only windows are supported but pull-req are welcome.

## License

This software is released under `CC-BY: Attribution` license. More about it [here](https://creativecommons.org/licenses/by/4.0/)