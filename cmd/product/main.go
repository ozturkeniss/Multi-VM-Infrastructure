package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"

	"cluster-iac/api/proto/product"
	"cluster-iac/internal/product/config"
	"cluster-iac/internal/product/database"
	"cluster-iac/internal/product/handler"
	"cluster-iac/internal/product/repository"
	"cluster-iac/internal/product/service"

	"github.com/gin-gonic/gin"
	"google.golang.org/grpc"
)

func main() {
	// Config yükle
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Database bağlantısı
	err = database.ConnectDB(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// Repository, service ve handler oluştur
	productRepo := repository.NewProductRepository(database.DB)
	productService := service.NewProductService(productRepo)
	productHandler := handler.NewProductHandler(productService)

	// gRPC server başlat
	go startGRPCServer(cfg, productService)

	// HTTP server başlat
	startHTTPServer(cfg, productHandler)
}

func startGRPCServer(cfg *config.Config, productService service.ProductService) {
	lis, err := net.Listen("tcp", fmt.Sprintf(":%s", "50051"))
	if err != nil {
		log.Fatalf("Failed to listen for gRPC: %v", err)
	}

	grpcServer := grpc.NewServer()
	product.RegisterProductServiceServer(grpcServer, &grpcProductServer{productService: productService})

	log.Printf("gRPC server starting on port 50051")
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve gRPC: %v", err)
	}
}

func startHTTPServer(cfg *config.Config, productHandler *handler.ProductHandler) {
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

	// Product routes
	products := r.Group("/products")
	{
		products.POST("/", productHandler.CreateProduct)
		products.GET("/", productHandler.GetAllProducts)
		products.GET("/category", productHandler.GetProductsByCategory)
		products.GET("/:id", productHandler.GetProductByID)
		products.PUT("/:id", productHandler.UpdateProduct)
		products.DELETE("/:id", productHandler.DeleteProduct)
	}

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "OK", "service": "product-service"})
	})
	r.HEAD("/health", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})

	// Server başlat
	serverAddr := fmt.Sprintf(":%s", cfg.ServerPort)
	log.Printf("HTTP server starting on port %s", cfg.ServerPort)
	
	if err := r.Run(serverAddr); err != nil {
		log.Fatalf("Failed to start HTTP server: %v", err)
	}
}

// gRPC server implementasyonu
type grpcProductServer struct {
	product.UnimplementedProductServiceServer
	productService service.ProductService
}

func (s *grpcProductServer) GetProduct(ctx context.Context, req *product.GetProductRequest) (*product.GetProductResponse, error) {
	prod, err := s.productService.GetProductByID(uint(req.Id))
	if err != nil {
		return nil, err
	}

	return &product.GetProductResponse{
		Product: &product.Product{
			Id:          uint32(prod.ID),
			Name:        prod.Name,
			Description: prod.Description,
			Price:       prod.Price,
			Stock:       int32(prod.Stock),
			Category:    prod.Category,
			ImageUrl:    prod.ImageURL,
			CreatedAt:   prod.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
			UpdatedAt:   prod.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
		},
	}, nil
}

func (s *grpcProductServer) GetProducts(ctx context.Context, req *product.GetProductsRequest) (*product.GetProductsResponse, error) {
	var products []*product.Product
	
	for _, id := range req.Ids {
		prod, err := s.productService.GetProductByID(uint(id))
		if err != nil {
			continue // Hata durumunda bu ürünü atla
		}
		
		products = append(products, &product.Product{
			Id:          uint32(prod.ID),
			Name:        prod.Name,
			Description: prod.Description,
			Price:       prod.Price,
			Stock:       int32(prod.Stock),
			Category:    prod.Category,
			ImageUrl:    prod.ImageURL,
			CreatedAt:   prod.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
			UpdatedAt:   prod.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
		})
	}

	return &product.GetProductsResponse{Products: products}, nil
}
