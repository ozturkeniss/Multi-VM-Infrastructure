package service

import (
	"context"
	"fmt"

	"cluster-iac/api/proto/product"
	"cluster-iac/internal/basket/model"
	"cluster-iac/internal/basket/repository"
)

type BasketService interface {
	GetBasket(ctx context.Context, userID string) (*model.Basket, error)
	AddItem(ctx context.Context, userID string, productID uint, quantity int) error
	RemoveItem(ctx context.Context, userID string, productID uint) error
	UpdateItemQuantity(ctx context.Context, userID string, productID uint, quantity int) error
	ClearBasket(ctx context.Context, userID string) error
}

type basketService struct {
	repo         repository.BasketRepository
	productClient product.ProductServiceClient
}

func NewBasketService(repo repository.BasketRepository, productClient product.ProductServiceClient) BasketService {
	return &basketService{
		repo:         repo,
		productClient: productClient,
	}
}

func (s *basketService) GetBasket(ctx context.Context, userID string) (*model.Basket, error) {
	return s.repo.GetBasket(ctx, userID)
}

func (s *basketService) AddItem(ctx context.Context, userID string, productID uint, quantity int) error {
	// Product bilgilerini gRPC ile al
	productResp, err := s.productClient.GetProduct(ctx, &product.GetProductRequest{
		Id: uint32(productID),
	})
	if err != nil {
		return fmt.Errorf("failed to get product: %v", err)
	}

	// Basket item oluştur
	item := &model.BasketItem{
		ProductID:   productID,
		Name:        productResp.Product.Name,
		Description: productResp.Product.Description,
		Price:       productResp.Product.Price,
		ImageURL:    productResp.Product.ImageUrl,
		Quantity:    quantity,
	}

	return s.repo.AddItem(ctx, userID, item)
}

func (s *basketService) RemoveItem(ctx context.Context, userID string, productID uint) error {
	return s.repo.RemoveItem(ctx, userID, productID)
}

func (s *basketService) UpdateItemQuantity(ctx context.Context, userID string, productID uint, quantity int) error {
	return s.repo.UpdateItemQuantity(ctx, userID, productID, quantity)
}

func (s *basketService) ClearBasket(ctx context.Context, userID string) error {
	return s.repo.DeleteBasket(ctx, userID)
}
