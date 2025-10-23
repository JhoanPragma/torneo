# 🚀 Plataforma Serverless de Torneos E-Sports

Este repositorio contiene la infraestructura como código (IaC) con **Terraform** y el código fuente de las **AWS Lambda Functions** para una plataforma de torneos de videojuegos, diseñada para ser altamente escalable, resiliente y segura bajo el modelo Serverless de AWS.

## ⚙️ Arquitectura de Solución

La arquitectura es 100% Serverless y se despliega en AWS, asegurando alta disponibilidad y pago por uso.

| Componente | Función Principal |
| :--- | :--- |
| **Terraform** | Gestiona el 100% de la infraestructura (IaC). |
| **AWS API Gateway (HTTP)** | Punto de entrada para todas las rutas API (públicas y protegidas). |
| **AWS Cognito** | Autenticación de usuarios y autorización JWT para rutas protegidas. |
| **AWS Lambda (Node.js 18.x)** | Contiene la lógica de negocio (7 funciones modulares, ej: `ventas`, `torneos`, `auth-*`). |
| **Amazon DynamoDB** | Persistencia NoSQL de alto rendimiento (`Torneos`, `Ventas`, `Transmisiones`). |
| **Amazon S3** | Backend de estado de Terraform (`torneos-tfstate`) y almacenamiento de códigos QR (`torneos-qr-codes-dev`). |
| **Amazon SNS** | Envío de notificaciones a participantes y espectadores. |

## 🛠️ Prerrequisitos

Para instalar y desplegar el proyecto, necesitas tener instalados y configurados los siguientes componentes:

1.  **Node.js (v18+)** y **npm**: Necesarios para empaquetar las funciones Lambda.
2.  **Terraform (v1.5.0+)**: Herramienta de Infraestructura como Código.
3.  **AWS CLI**: Configurado y autenticado con las credenciales de tu cuenta.
    ```bash
    aws configure
    ```
4.  **Credenciales de AWS**: El usuario de IAM debe tener permisos para crear y modificar recursos en AWS (IAM, S3, DynamoDB, Lambda, API Gateway, Cognito, SNS).

## 🚀 Instalación y Despliegue (En AWS)

Dado que la infraestructura y el código se despliegan juntos a través de un pipeline, el proceso se realiza principalmente con Terraform.

### 1. Inicialización de Terraform

Navega al directorio raíz donde se encuentran los archivos `main.tf` y `variables.tf`.

```bash
# Inicializa Terraform, descargando los proveedores y configurando el S3 Backend
terraform init
```

### Rutas de Autenticación

Servicio,Método,Ruta,Función,Descripción
Auth,POST,/signup,auth-signup-lambda,Registra un nuevo usuario en Cognito.
Auth,POST,/confirm,auth-confirm-lambda,Confirma la cuenta de usuario con el código recibido por email.
Auth,POST,/login,auth-login-lambda,Inicia sesión y devuelve el token JWT (Auth Flow: ALLOW_USER_PASSWORD_AUTH).

Ejemplo:

```bash
POST https://{api_gateway_url}/signup
{
    "email": "usuario@ejemplo.com",
    "password": "Password123!"
}
```
### Rutas Tournament

Servicio,Método,Ruta,Función,Descripción
Torneos,POST,/torneos,crear-torneo-lambda,Crea un nuevo registro de torneo en DynamoDB.
Ventas,POST,/ventas,ventas-lambda,"Procesa una venta, calcula la comisión del 5% y guarda en la tabla Ventas."
QR,POST,/qr_generator,qr-generator-lambda,"Genera y sube el código QR de acceso a S3, actualizando la venta."
Notif.,POST,/notificaciones,notificaciones-lambda,Envía alertas vía SNS o bloquea enlaces de transmisión.

Ejemplo de request:

```bash
POST https://{api_gateway_url}/ventas
Authorization: Bearer eyJraWQiOiJ...
{
    "user_id": "uuid-del-usuario",
    "torneo_id": "uuid-del-torneo",
    "cantidad_tickets": 2,
    "precio_unitario": 50.00
}
```
