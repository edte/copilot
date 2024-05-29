@echo off
echo begin
set nvim_file_path=%USERPROFILE%\AppData\Local\nvim\pack\gongfeng
if exist "%nvim_file_path%" (
    rmdir /s /q "%nvim_file_path%"
    if %errorlevel%==0 (
        echo nvim deleted successfully.
    ) else (
        echo Failed to delete the file.
    )
) else (
  echo nvim deleted successfully.
)

set vim_file_path=%USERPROFILE%\vimfiles\pack\gongfeng
if exist "%vim_file_path%" (
    rmdir /s /q "%vim_file_path%"
    if %errorlevel%==0 (
        echo vim deleted successfully.
    ) else (
        echo Failed to delete the file.
    )
) else (
  echo vim deleted successfully.
)
echo end
pause
