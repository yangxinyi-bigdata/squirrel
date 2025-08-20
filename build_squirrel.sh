# 5. 构建 Squirrel
# 设置环境变量（根据需要调整）
export ARCHS='arm64'  # 构建通用二进制
export BUILD_UNIVERSAL=1

# 使用 make 构建
make

# 6. 打包成 .pkg 安装包
make package

# 7. 安装输入法
sudo installer -pkg package/Squirrel.pkg -target /

# 8. 重启输入法服务
sudo killall -KILL SquirrelInputController
# 然后在系统偏好设置中重新添加鼠须管输入法