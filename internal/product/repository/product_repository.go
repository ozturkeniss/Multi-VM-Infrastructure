package repository

import (
	"cluster-iac/internal/product/model"
	"gorm.io/gorm"
)

type ProductRepository interface {
	Create(product *model.Product) error
	GetByID(id uint) (*model.Product, error)
	GetAll() ([]model.Product, error)
	Update(product *model.Product) error
	Delete(id uint) error
	GetByCategory(category string) ([]model.Product, error)
}

type productRepository struct {
	db *gorm.DB
}

func NewProductRepository(db *gorm.DB) ProductRepository {
	return &productRepository{db: db}
}

func (r *productRepository) Create(product *model.Product) error {
	return r.db.Create(product).Error
}

func (r *productRepository) GetByID(id uint) (*model.Product, error) {
	var product model.Product
	err := r.db.First(&product, id).Error
	if err != nil {
		return nil, err
	}
	return &product, nil
}

func (r *productRepository) GetAll() ([]model.Product, error) {
	var products []model.Product
	err := r.db.Find(&products).Error
	return products, err
}

func (r *productRepository) Update(product *model.Product) error {
	return r.db.Save(product).Error
}

func (r *productRepository) Delete(id uint) error {
	var product model.Product
	return r.db.Delete(&product, id).Error
}

func (r *productRepository) GetByCategory(category string) ([]model.Product, error) {
	var products []model.Product
	err := r.db.Where("category = ?", category).Find(&products).Error
	return products, err
}
