@echo off
echo begin

cd ..
set plugin_directory_path="%cd%\vim"

set nvim_file_path=%USERPROFILE%\AppData\Local\nvim\pack\gongfeng\start
if not exist "%nvim_file_path%" (
  mkdir "%nvim_file_path%"
)
set nvim_file_ln_path=%USERPROFILE%\AppData\Local\nvim\pack\gongfeng\start\vim
if exist "%nvim_file_ln_path%" (
  rmdir /s /q "%nvim_file_ln_path%"
)
mklink /D "%nvim_file_ln_path%" "%plugin_directory_path%"

set vim_file_path=%USERPROFILE%\vimfiles\pack\gongfeng\start
if not exist "%vim_file_path%" (
  mkdir "%vim_file_path%"
)
set vim_file_ln_path=%USERPROFILE%\vimfiles\pack\gongfeng\start\vim
if exist "%vim_file_ln_path%" (
  rmdir /s /q "%vim_file_ln_path%"
)
mklink /D "%vim_file_ln_path%" ""%plugin_directory_path%""


echo end
pause
