package model

import (
	"time"
)

type BasketItem struct {
	ProductID   uint    `json:"product_id"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Price       float64 `json:"price"`
	ImageURL    string  `json:"image_url"`
	Quantity    int     `json:"quantity"`
}

type Basket struct {
	UserID    string       `json:"user_id"`
	Items     []BasketItem `json:"items"`
	Total     float64      `json:"total"`
	CreatedAt time.Time    `json:"created_at"`
	UpdatedAt time.Time    `json:"updated_at"`
}
