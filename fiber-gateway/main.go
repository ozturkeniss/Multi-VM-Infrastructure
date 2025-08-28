package main

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
)

type Config struct {
	ProductServiceURL string
	BasketServiceURL string
	GatewayPort      string
}

func main() {
	// Environment variables'dan config'i al
	productServiceURL := getEnv("PRODUCT_SERVICE_URL", "http://localhost:8080")
	basketServiceURL := getEnv("BASKET_SERVICE_URL", "http://localhost:8081")
	gatewayPort := getEnv("GATEWAY_PORT", "8082")

	config := &Config{
		ProductServiceURL: productServiceURL,
		BasketServiceURL: basketServiceURL,
		GatewayPort:      gatewayPort,
	}

	app := fiber.New(fiber.Config{
		AppName: "Cluster IAC API Gateway",
	})

	// Middleware
	app.Use(logger.New())
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowMethods: "GET,POST,PUT,DELETE,OPTIONS",
		AllowHeaders: "Origin,Content-Type,Accept,Authorization",
	}))

	// Health check
	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status":  "OK",
			"service": "api-gateway",
			"port":    config.GatewayPort,
		})
	})

	// Product Service Routes
	productGroup := app.Group("/api/products")
	{
		productGroup.Post("/", proxyToService(config.ProductServiceURL+"/products/", "POST"))
		productGroup.Get("/", proxyToService(config.ProductServiceURL+"/products/", "GET"))
		productGroup.Get("/category", proxyToService(config.ProductServiceURL+"/products/category", "GET"))
		productGroup.Get("/:id", proxyToService(config.ProductServiceURL+"/products/:id", "GET"))
		productGroup.Put("/:id", proxyToService(config.ProductServiceURL+"/products/:id", "PUT"))
		productGroup.Delete("/:id", proxyToService(config.ProductServiceURL+"/products/:id", "DELETE"))
	}

	// Basket Service Routes
	basketGroup := app.Group("/api/baskets")
	{
		basketGroup.Get("/:user_id", proxyToService(config.BasketServiceURL+"/baskets/:user_id", "GET"))
		basketGroup.Post("/:user_id/items", proxyToService(config.BasketServiceURL+"/baskets/:user_id/items", "POST"))
		basketGroup.Delete("/:user_id/items/:product_id", proxyToService(config.BasketServiceURL+"/baskets/:user_id/items/:product_id", "DELETE"))
		basketGroup.Put("/:user_id/items/:product_id", proxyToService(config.BasketServiceURL+"/baskets/:user_id/items/:product_id", "PUT"))
		basketGroup.Delete("/:user_id", proxyToService(config.BasketServiceURL+"/baskets/:user_id", "DELETE"))
	}

	// Legacy routes (without /api prefix for backward compatibility)
	app.Post("/products", proxyToService(config.ProductServiceURL+"/products/", "POST"))
	app.Get("/products", proxyToService(config.ProductServiceURL+"/products/", "GET"))
	app.Get("/products/category", proxyToService(config.ProductServiceURL+"/products/category", "GET"))
	app.Get("/products/:id", proxyToService(config.ProductServiceURL+"/products/:id", "GET"))
	app.Put("/products/:id", proxyToService(config.ProductServiceURL+"/products/:id", "PUT"))
	app.Delete("/products/:id", proxyToService(config.ProductServiceURL+"/products/:id", "DELETE"))

	app.Get("/baskets/:user_id", proxyToService(config.BasketServiceURL+"/baskets/:user_id", "GET"))
	app.Post("/baskets/:user_id/items", proxyToService(config.BasketServiceURL+"/baskets/:user_id/items", "POST"))
	app.Delete("/baskets/:user_id/items/:product_id", proxyToService(config.BasketServiceURL+"/baskets/:user_id/items/:product_id", "DELETE"))
	app.Put("/baskets/:user_id/items/:product_id", proxyToService(config.BasketServiceURL+"/baskets/:user_id/items/:product_id", "PUT"))
	app.Delete("/baskets/:user_id", proxyToService(config.BasketServiceURL+"/baskets/:user_id", "DELETE"))

	log.Printf("API Gateway starting on port %s", config.GatewayPort)
	log.Fatal(app.Listen(fmt.Sprintf(":%s", config.GatewayPort)))
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func proxyToService(targetURL string, method string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// URL parametrelerini hedef URL'e ekle
		url := targetURL
		for key, value := range c.AllParams() {
			url = strings.Replace(url, ":"+key, value, -1)
		}

		// Query parametrelerini ekle
		if len(c.Context().QueryArgs().QueryString()) > 0 {
			url += "?" + string(c.Context().QueryArgs().QueryString())
		}

		// Request body'yi oku
		var body io.Reader
		if method == "POST" || method == "PUT" {
			body = bytes.NewReader(c.Body())
		}

		// HTTP request oluştur
		req, err := http.NewRequest(method, url, body)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to create request",
			})
		}

		// Headers'ı kopyala
		c.Request().Header.VisitAll(func(key, value []byte) {
			if string(key) != "Host" {
				req.Header.Set(string(key), string(value))
			}
		})

		// Content-Type header'ı ekle
		if method == "POST" || method == "PUT" {
			req.Header.Set("Content-Type", "application/json")
		}

		// HTTP client ile request'i gönder
		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			return c.Status(fiber.StatusBadGateway).JSON(fiber.Map{
				"error": "Failed to forward request",
			})
		}
		defer resp.Body.Close()

		// Response body'yi oku
		respBody, err := io.ReadAll(resp.Body)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to read response",
			})
		}

		// Response headers'ı kopyala
		for key, values := range resp.Header {
			for _, value := range values {
				c.Set(key, value)
			}
		}

		// Response'u döndür
		return c.Status(resp.StatusCode).Send(respBody)
	}
}
