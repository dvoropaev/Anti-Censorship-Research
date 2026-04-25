#!/bin/bash

echo "================================================"
echo ""
echo "Printing info about system and tools"
echo ""
echo ""

echo "System info printing..."
sw_vers
echo ""

echo "Xcode info printing..."
xed --version
echo ""

echo "Swift info printing..."
swift --version
echo ""

echo "Python info printing..."
python3 --version
echo ""

echo "Ruby info printing..."
ruby --version
which ruby
echo ""

echo "Bundler info printing..."
bundle --version
echo ""

echo "Flutter info printing..."
flutter --version
echo ""


echo "Which terminal is used printing..."
echo $0
echo ""

echo "================================================"
exit 0
