package main

import (
	"context"
	"fmt"
	"log"
	"net/http"

	"cluster-iac/api/proto/product"
	"cluster-iac/internal/basket/config"
	"cluster-iac/internal/basket/handler"
	"cluster-iac/internal/basket/repository"
	"cluster-iac/internal/basket/service"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	// Config yükle
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Redis bağlantısı
	redisClient := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
		DB:       0,
	})

	// Redis bağlantısını test et
	ctx := context.Background()
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}
	log.Println("Redis connected successfully")

	// gRPC product client bağlantısı
	productConn, err := grpc.Dial(cfg.ProductGRPC, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("Failed to connect to product service: %v", err)
	}
	defer productConn.Close()

	productClient := product.NewProductServiceClient(productConn)
	log.Println("Product service gRPC client connected successfully")

	// Repository, service ve handler oluştur
	basketRepo := repository.NewBasketRepository(redisClient)
	basketService := service.NewBasketService(basketRepo, productClient)
	basketHandler := handler.NewBasketHandler(basketService)

	// Gin router oluştur
	r := gin.Default()

	// CORS middleware ekle
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization")
		
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusOK)
			return
		}
		
		c.Next()
	})

	// Basket routes
	baskets := r.Group("/baskets")
	{
		baskets.GET("/:user_id", basketHandler.GetBasket)
		baskets.POST("/:user_id/items", basketHandler.AddItem)
		baskets.DELETE("/:user_id/items/:product_id", basketHandler.RemoveItem)
		baskets.PUT("/:user_id/items/:product_id", basketHandler.UpdateItemQuantity)
		baskets.DELETE("/:user_id", basketHandler.ClearBasket)
	}

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "OK", "service": "basket-service"})
	})
	r.HEAD("/health", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	// Server başlat
	serverAddr := fmt.Sprintf(":%s", cfg.ServerPort)
	log.Printf("Basket service starting on port %s", cfg.ServerPort)
	
	if err := r.Run(serverAddr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
