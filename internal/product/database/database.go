package database

import (
	"fmt"
	"log"

	"cluster-iac/internal/product/config"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var DB *gorm.DB

func ConnectDB(cfg *config.Config) error {
	dsn := fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=%s",
		cfg.DBHost, cfg.DBUser, cfg.DBPassword, cfg.DBName, cfg.DBPort, cfg.DBSSLMode)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		return fmt.Errorf("failed to connect to database: %v", err)
	}

	DB = db
	log.Println("Database connected successfully")

	// AutoMigrate ile tabloları oluştur
	err = AutoMigrate()
	if err != nil {
		return fmt.Errorf("failed to auto migrate: %v", err)
	}

	return nil
}

func AutoMigrate() error {
	// Product modelini migrate et
	err := DB.AutoMigrate(&Product{})
	if err != nil {
		return fmt.Errorf("failed to migrate Product table: %v", err)
	}

	log.Println("Database migration completed successfully")
	return nil
}
