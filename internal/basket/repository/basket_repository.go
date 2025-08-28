package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"cluster-iac/internal/basket/model"
	"github.com/go-redis/redis/v8"
)

type BasketRepository interface {
	GetBasket(ctx context.Context, userID string) (*model.Basket, error)
	SaveBasket(ctx context.Context, basket *model.Basket) error
	DeleteBasket(ctx context.Context, userID string) error
	AddItem(ctx context.Context, userID string, item *model.BasketItem) error
	RemoveItem(ctx context.Context, userID string, productID uint) error
	UpdateItemQuantity(ctx context.Context, userID string, productID uint, quantity int) error
}

type basketRepository struct {
	redisClient *redis.Client
}

func NewBasketRepository(redisClient *redis.Client) BasketRepository {
	return &basketRepository{redisClient: redisClient}
}

func (r *basketRepository) GetBasket(ctx context.Context, userID string) (*model.Basket, error) {
	key := fmt.Sprintf("basket:%s", userID)
	data, err := r.redisClient.Get(ctx, key).Result()
	if err == redis.Nil {
		// Basket bulunamadı, yeni oluştur
		return &model.Basket{
			UserID:    userID,
			Items:     []model.BasketItem{},
			Total:     0,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}, nil
	} else if err != nil {
		return nil, err
	}

	var basket model.Basket
	if err := json.Unmarshal([]byte(data), &basket); err != nil {
		return nil, err
	}

	return &basket, nil
}

func (r *basketRepository) SaveBasket(ctx context.Context, basket *model.Basket) error {
	key := fmt.Sprintf("basket:%s", basket.UserID)
	basket.UpdatedAt = time.Now()

	data, err := json.Marshal(basket)
	if err != nil {
		return err
	}

	// 24 saat TTL ile kaydet
	return r.redisClient.Set(ctx, key, data, 24*time.Hour).Err()
}

func (r *basketRepository) DeleteBasket(ctx context.Context, userID string) error {
	key := fmt.Sprintf("basket:%s", userID)
	return r.redisClient.Del(ctx, key).Err()
}

func (r *basketRepository) AddItem(ctx context.Context, userID string, item *model.BasketItem) error {
	basket, err := r.GetBasket(ctx, userID)
	if err != nil {
		return err
	}

	// Mevcut item'ı kontrol et
	for i, existingItem := range basket.Items {
		if existingItem.ProductID == item.ProductID {
			// Miktarı güncelle
			basket.Items[i].Quantity += item.Quantity
			basket.Total = r.calculateTotal(basket.Items)
			return r.SaveBasket(ctx, basket)
		}
	}

	// Yeni item ekle
	basket.Items = append(basket.Items, *item)
	basket.Total = r.calculateTotal(basket.Items)
	return r.SaveBasket(ctx, basket)
}

func (r *basketRepository) RemoveItem(ctx context.Context, userID string, productID uint) error {
	basket, err := r.GetBasket(ctx, userID)
	if err != nil {
		return err
	}

	for i, item := range basket.Items {
		if item.ProductID == productID {
			basket.Items = append(basket.Items[:i], basket.Items[i+1:]...)
			basket.Total = r.calculateTotal(basket.Items)
			return r.SaveBasket(ctx, basket)
		}
	}

	return nil
}

func (r *basketRepository) UpdateItemQuantity(ctx context.Context, userID string, productID uint, quantity int) error {
	basket, err := r.GetBasket(ctx, userID)
	if err != nil {
		return err
	}

	for i, item := range basket.Items {
		if item.ProductID == productID {
			if quantity <= 0 {
				// Miktar 0 veya daha az ise item'ı kaldır
				basket.Items = append(basket.Items[:i], basket.Items[i+1:]...)
			} else {
				basket.Items[i].Quantity = quantity
			}
			basket.Total = r.calculateTotal(basket.Items)
			return r.SaveBasket(ctx, basket)
		}
	}

	return nil
}

func (r *basketRepository) calculateTotal(items []model.BasketItem) float64 {
	total := 0.0
	for _, item := range items {
		total += item.Price * float64(item.Quantity)
	}
	return total
}
