package config

import (
	"os"

	"github.com/joho/godotenv"
)

type Config struct {
	RedisAddr     string
	RedisPassword string
	RedisDB       string
	ServerPort    string
	ProductGRPC   string
}

func LoadConfig() (*Config, error) {
	// Container ortamında dosya olmayabilir; hata vermeden devam et
	_ = godotenv.Load("config.env")

	return &Config{
		RedisAddr:     os.Getenv("REDIS_ADDR"),
		RedisPassword: os.Getenv("REDIS_PASSWORD"),
		RedisDB:       os.Getenv("REDIS_DB"),
		ServerPort:    os.Getenv("BASKET_SERVER_PORT"),
		ProductGRPC:   os.Getenv("PRODUCT_GRPC_ADDR"),
	}, nil
}
