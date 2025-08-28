package service

import (
	"cluster-iac/internal/product/model"
	"cluster-iac/internal/product/repository"
)

type ProductService interface {
	CreateProduct(product *model.Product) error
	GetProductByID(id uint) (*model.Product, error)
	GetAllProducts() ([]model.Product, error)
	UpdateProduct(product *model.Product) error
	DeleteProduct(id uint) error
	GetProductsByCategory(category string) ([]model.Product, error)
}

type productService struct {
	repo repository.ProductRepository
}

func NewProductService(repo repository.ProductRepository) ProductService {
	return &productService{repo: repo}
}

func (s *productService) CreateProduct(product *model.Product) error {
	return s.repo.Create(product)
}

func (s *productService) GetProductByID(id uint) (*model.Product, error) {
	return s.repo.GetByID(id)
}

func (s *productService) GetAllProducts() ([]model.Product, error) {
	return s.repo.GetAll()
}

func (s *productService) UpdateProduct(product *model.Product) error {
	return s.repo.Update(product)
}

func (s *productService) DeleteProduct(id uint) error {
	return s.repo.Delete(id)
}

func (s *productService) GetProductsByCategory(category string) ([]model.Product, error) {
	return s.repo.GetByCategory(category)
}
