package main

import (
	docs "employee-api/docs"
	middlewares "employee-api/middleware"
	routes "employee-api/routes"
	"github.com/gin-gonic/gin"
	"github.com/penglongli/gin-metrics/ginmetrics"
	"github.com/sirupsen/logrus"
	swaggerfiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

func init() {
	logrus.SetLevel(logrus.InfoLevel)
	logrus.SetFormatter(&logrus.JSONFormatter{})
}

func main() {
	// Set Gin to release mode for production
	gin.SetMode(gin.ReleaseMode)
	router := gin.New()

	// Metrics setup
	monitor := ginmetrics.GetMonitor()
	monitor.SetMetricPath("/metrics")
	monitor.SetSlowTime(1)
	monitor.SetDuration([]float64{0.1, 0.3, 1.2, 5, 10})
	monitor.Use(router)

	// Middleware
	router.Use(gin.Recovery())
	router.Use(middlewares.LoggingMiddleware())

	// API Routes
	v1 := router.Group("/api/v1")
	docs.SwaggerInfo.BasePath = "/api/v1/employee"
	routes.CreateRouterForEmployee(v1)

	// Swagger UI with dynamic host
	router.GET("/swagger/*any", func(c *gin.Context) {
		// Dynamically set Swagger host from request
		docs.SwaggerInfo.Host = c.Request.Host
		ginSwagger.WrapHandler(swaggerfiles.Handler)(c)
	})

	// Start server
	if err := router.Run(":8080"); err != nil {
		logrus.Fatalf("Failed to start server: %v", err)
	}
}
