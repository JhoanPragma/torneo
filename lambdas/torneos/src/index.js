const { DynamoDBClient, PutItemCommand, ScanCommand, GetItemCommand } = require("@aws-sdk/client-dynamodb"); // <-- AÑADIDO: GetItemCommand
const { v4: uuidv4 } = require('uuid');

const REGION = process.env.AWS_REGION || 'us-east-1';
const TABLE_NAME = process.env.TABLE_NAME || 'Torneos';
// Nuevas variables de entorno para las tablas de catálogo
const CATEGORIAS_TABLE = process.env.CATEGORIAS_TABLE || 'Categorias';
const TIPOS_JUEGO_TABLE = process.env.TIPOS_JUEGO_TABLE || 'TiposJuego'; 

const client = new DynamoDBClient({ region: REGION });

const MAX_FREE_TOURNAMENTS = 2; // Límite máximo de torneos gratuitos

/**
 * Función de soporte para verificar si un código existe en una tabla de catálogo.
 */
const checkCatalog = async (tableName, keyValue) => {
    const params = {
        TableName: tableName,
        Key: {
            "codigo": { S: keyValue }
        },
        // Solo necesitamos saber si el ítem existe
        ProjectionExpression: "codigo" 
    };
    const command = new GetItemCommand(params);
    const data = await client.send(command);
    return !!data.Item;
};


/**
 * Handler de la función Lambda para la creación de torneos.
 * 1. Valida catálogos (Categoría y Tipo de Juego).
 * 2. Valida el límite de torneos gratuitos (2 por organizador).
 * 3. Crea el torneo.
 */
exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        // Se asume que 'tipo_juego' debe venir en el body para la validación de catálogo
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
        // 1. VALIDACIÓN DE CATÁLOGOS (NUEVO REQUISITO)
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
        // 2. VALIDACIÓN: Límite de 2 Torneos Gratuitos (Existente)
        // =========================================================
        if (tipo_torneo === "gratuito") {
            const scanParams = {
                TableName: TABLE_NAME,
                // Usamos FilterExpression para buscar por organizador y tipo
                FilterExpression: "organizador_id = :org_id AND tipo = :tipo_t",
                ExpressionAttributeValues: {
                    ":org_id": { S: organizador_id },
                    ":tipo_t": { S: "gratuito" }
                },
                // Pedimos solo el Count, sin traer todos los Item (optimización de lectura)
                Select: "COUNT" 
            };
            
            const scanCommand = new ScanCommand(scanParams);
            const data = await client.send(scanCommand);
            
            const existingFreeTournaments = data.Count || 0;

            if (existingFreeTournaments >= MAX_FREE_TOURNAMENTS) {
                return {
                    statusCode: 403,
                    body: JSON.stringify({ 
                        message: `Límite alcanzado. El organizador (${organizador_id}) ya ha creado el máximo de ${MAX_FREE_TOURNAMENTS} torneos gratuitos permitidos.` 
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