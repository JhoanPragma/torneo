const { DynamoDBClient, PutItemCommand, ScanCommand } = require("@aws-sdk/client-dynamodb"); // <-- AÑADIDO: ScanCommand
const { v4: uuidv4 } = require('uuid');

const REGION = process.env.AWS_REGION || 'us-east-1';
const TABLE_NAME = processs.env.TABLE_NAME || 'Torneos';
const client = new DynamoDBClient({ region: REGION });

const MAX_FREE_TOURNAMENTS = 2; // Límite máximo de torneos gratuitos

/**
 * Handler de la función Lambda para la creación de torneos.
 * Valida el límite de torneos gratuitos por organizador,
 * asigna la categoría y el tipo (gratuito/pago),
 * y guarda la información en DynamoDB.
 */
exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { nombre, descripcion, fecha_inicio, fecha_fin, organizador_id, categoria, es_pago } = body;

        // Validaciones de entrada
        if (!nombre || !organizador_id || !categoria) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Nombre, organizador_id y categoría son obligatorios." })
            };
        }

        const torneoId = uuidv4();
        const tipo_torneo = es_pago ? "pago" : "gratuito";
        
        // =========================================================
        // 1. VALIDACIÓN: Límite de 2 Torneos Gratuitos
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
        
        // 2. Creación del Torneo
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
                message: "Torneo creado exitosamente.",
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