const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, ScanCommand } = require("@aws-sdk/lib-dynamodb");

const REGION = process.env.AWS_REGION || 'us-east-1';
const USER_PROFILES_TABLE = process.env.USER_PROFILES_TABLE; // 'UserProfiles'
const TOURNAMENTS_TABLE = process.env.TABLE_NAME; // 'Torneos'
const client = new DynamoDBClient({ region: REGION });
const ddbDocClient = DynamoDBDocumentClient.from(client);

const REQUIRED_ROLE = "ADMINISTRADOR_GLOBAL";

/**
 * Función de soporte para obtener el rol del usuario autenticado.
 * Usa el email del token JWT para consultar la tabla UserProfiles.
 */
const getUserRole = async (email) => {
    const params = {
        TableName: USER_PROFILES_TABLE,
        Key: { id: email } // El email es la Hash Key en UserProfiles
    };
    
    // Usamos GetCommand para eficiencia
    const { Item } = await ddbDocClient.send(new GetCommand(params));
    return Item ? Item.role : "PARTICIPANTE"; 
};

/**
 * Handler de la función Lambda: GET /dashboard/torneos
 * Restringido a usuarios con el rol ADMINISTRADOR_GLOBAL.
 * Trae todos los torneos.
 */
exports.handler = async (event) => {
    try {
        // El email se extrae de las claims del token de Cognito, inyectadas por API Gateway.
        const authenticatedEmail = event.requestContext?.authorizer?.claims?.email;

        if (!authenticatedEmail) {
            return {
                statusCode: 401,
                body: JSON.stringify({ message: "Acceso denegado: Token de autorización inválido o ausente." })
            };
        }

        // 1. Verificar el Rol del Usuario
        const userRole = await getUserRole(authenticatedEmail);

        if (userRole !== REQUIRED_ROLE) {
            return {
                statusCode: 403,
                body: JSON.stringify({ 
                    message: `Acceso denegado. Rol actual: ${userRole}. Se requiere el rol: ${REQUIRED_ROLE}.` 
                })
            };
        }

        // 2. Si es ADMINISTRADOR_GLOBAL, realizar el Scan de todos los torneos
        const scanParams = {
            TableName: TOURNAMENTS_TABLE,
        };

        const { Items } = await ddbDocClient.send(new ScanCommand(scanParams));
        
        return {
            statusCode: 200,
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                message: "Consulta de torneos completa para el dashboard de administrador.",
                role: userRole,
                total_torneos: Items.length,
                torneos: Items
            })
        };

    } catch (error) {
        console.error("Error en la consulta del dashboard:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Error interno del servidor", error: error.message })
        };
    }
};