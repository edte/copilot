@echo off
set nvim_directory_path=%USERPROFILE%\AppData\Local\nvim\pack\gongfeng
set vim_directory_path=%USERPROFILE%\vimfiles\pack\gongfeng

echo Are you sure to remove: %nvim_directory_path% and %vim_directory_path% ?(y/n)
set /p confirmation=
if /I "%confirmation%"=="y" (
  if exist "%nvim_directory_path%" (
    rmdir /s /q "%nvim_directory_path%"
    echo %nvim_directory_path% has been removed.
  )
  if exist "%vim_directory_path%" (
    rmdir /s /q "%vim_directory_path%"
    echo %vim_directory_path% has been removed.
  )
)

echo Done.
pause
