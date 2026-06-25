@echo off

cd..
git add .
set /p commitmessage=type a commit message : 
git commit -m "%commitmessage%"
git push
echo Press Enter...
read