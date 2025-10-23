const { DynamoDBClient, PutItemCommand, ScanCommand, GetItemCommand } = require("@aws-sdk/client-dynamodb");
const { v4: uuidv4 } = require('uuid');

const REGION = process.env.AWS_REGION || 'us-east-1';
const TABLE_NAME = process.env.TABLE_NAME || 'Torneos';
// Variables de entorno para las tablas de catálogo y perfiles
const CATEGORIAS_TABLE = process.env.CATEGORIAS_TABLE || 'Categorias';
const TIPOS_JUEGO_TABLE = process.env.TIPOS_JUEGO_TABLE || 'TiposJuego'; 
const USER_PROFILES_TABLE = process.env.USER_PROFILES_TABLE || 'UserProfiles'; // Tabla de perfiles

const client = new DynamoDBClient({ region: REGION });

// Definición de límites basada en roles
const ROLE_LIMITS = {
    "ORGANIZADOR": 2, // Límite para organizadores
    "PARTICIPANTE": 1, // Límite para usuarios registrados generales
    "DEFAULT": 1 
};

/**
 * Función de soporte para verificar si un código existe en una tabla de catálogo.
 */
const checkCatalog = async (tableName, keyValue) => {
    const params = {
        TableName: tableName,
        Key: {
            "codigo": { S: keyValue }
        },
        ProjectionExpression: "codigo" 
    };
    const command = new GetItemCommand(params);
    const data = await client.send(command);
    return !!data.Item;
};

/**
 * Obtiene el rol del usuario de la tabla UserProfiles.
 */
const getUserRole = async (userId) => {
    const params = {
        TableName: USER_PROFILES_TABLE,
        Key: {
            "id": { S: userId } // El organizador_id es el ID de usuario (email)
        },
        ProjectionExpression: "role"
    };
    const command = new GetItemCommand(params);
    const data = await client.send(command);
    
    if (data.Item && data.Item.role && data.Item.role.S) {
        return data.Item.role.S;
    }
    // Si no se encuentra, retorna el rol por defecto
    return "PARTICIPANTE"; 
};


/**
 * Handler de la función Lambda para la creación de torneos.
 * 1. Valida catálogos.
 * 2. Valida el límite de torneos gratuitos (dinámico por rol).
 * 3. Crea el torneo.
 */
exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { nombre, descripcion, fecha_inicio, fecha_fin, organizador_id, categoria, tipo_juego, es_pago } = body; 

        // Validaciones de entrada
        if (!nombre || !organizador_id || !categoria || !tipo_juego) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Nombre, organizador_id, categoria y tipo_juego son obligatorios." })
            };
        }

        const torneoId = uuidv4();
        const tipo_torneo = es_pago ? "pago" : "gratuito";

        // =========================================================
        // 1. VALIDACIÓN DE CATÁLOGOS
        // =========================================================
        const categoryExists = await checkCatalog(CATEGORIAS_TABLE, categoria);
        if (!categoryExists) {
             return {
                statusCode: 400,
                body: JSON.stringify({ message: `La categoría '${categoria}' no es válida. Debe ser seleccionada del catálogo.` })
            };
        }
        
        const gameTypeExists = await checkCatalog(TIPOS_JUEGO_TABLE, tipo_juego);
        if (!gameTypeExists) {
             return {
                statusCode: 400,
                body: JSON.stringify({ message: `El tipo de juego '${tipo_juego}' no es válido. Debe ser seleccionado del catálogo.` })
            };
        }


        // =========================================================
        // 2. VALIDACIÓN DE LÍMITES POR ROL
        // =========================================================
        if (tipo_torneo === "gratuito") {
            
            const userRole = await getUserRole(organizador_id);
            const maxLimit = ROLE_LIMITS[userRole] || ROLE_LIMITS["DEFAULT"];

            const scanParams = {
                TableName: TABLE_NAME,
                FilterExpression: "organizador_id = :org_id AND tipo = :tipo_t",
                ExpressionAttributeValues: {
                    ":org_id": { S: organizador_id },
                    ":tipo_t": { S: "gratuito" }
                },
                Select: "COUNT" 
            };
            
            const scanCommand = new ScanCommand(scanParams);
            const data = await client.send(scanCommand);
            
            const existingFreeTournaments = data.Count || 0;

            if (existingFreeTournaments >= maxLimit) {
                return {
                    statusCode: 403,
                    body: JSON.stringify({ 
                        message: `Límite alcanzado para el rol ${userRole}. Ya ha creado el máximo de ${maxLimit} torneos gratuitos permitidos.` 
                    })
                };
            }
        }
        // =========================================================
        
        // 3. Creación del Torneo
        // Parámetros para DynamoDB
        const params = {
            TableName: TABLE_NAME,
            Item: {
                id: { S: torneoId },
                nombre: { S: nombre },
                descripcion: { S: descripcion || "Sin descripción" },
                fecha_inicio: { S: fecha_inicio || "No especificado" },
                fecha_fin: { S: fecha_fin || "No especificado" },
                organizador_id: { S: organizador_id },
                categoria: { S: categoria },
                tipo_juego: { S: tipo_juego },
                tipo: { S: tipo_torneo },
                participantes: { N: "0" },
                audiencia: { N: "0" }
            }
        };

        const command = new PutItemCommand(params);
        await client.send(command);

        return {
            statusCode: 201,
            body: JSON.stringify({
                message: "Torneo creado exitosamente. Catálogos validados.",
                torneo_id: torneoId,
                tipo: tipo_torneo
            })
        };

    } catch (error) {
        console.error("Error al crear el torneo:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Error interno del servidor", error: error.message })
        };
    }
};