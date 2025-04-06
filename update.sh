# fetch updates
echo "Getting changes..."
git pull --recursive

# novaGround build
echo "Building novaGround..."
cd novaground/ && meson compile -C build
cd ..

# backend build
echo "Building FastAPI container..."
cd novaOps-back/ && sudo docker-compose build
cd ..

# frontend build
echo "Building novaOPS-front..."
cd novaOps-front/ && npm install
cd ..