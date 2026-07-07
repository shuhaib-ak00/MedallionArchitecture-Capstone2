FROM python:3.10-slim

# Set working directory di dalam container
WORKDIR /app

# Copy requirements.txt lebih dulu untuk memanfaatkan caching Docker
COPY requirements.txt .

# Install semua library yang ada di requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy seluruh kode aplikasi Anda ke dalam container
COPY . .