const { DynamoDBClient, UpdateItemCommand, GetItemCommand } = require("@aws-sdk/client-dynamodb");

const REGION = process.env.AWS_REGION || 'us-east-1';
const TABLE_NAME = process.env.TABLE_NAME || 'Torneos'; // Nombre de la tabla de torneos
const client = new DynamoDBClient({ region: REGION });

const MAX_SUB_ADMINS = 2; // Máximo permitido por el requisito de la prueba técnica

/**
 * Endpoint: PUT /torneos/sub-admins
 * Permite a un organizador agregar un subadministrador a un torneo.
 * Requisito: Máximo 2 subadministradores por evento.
 */
exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { torneo_id, sub_admin_id } = body;

        // 1. Validaciones básicas
        if (!torneo_id || !sub_admin_id) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "torneo_id y sub_admin_id son obligatorios." })
            };
        }

        const updateParams = {
            TableName: TABLE_NAME,
            Key: {
                id: { S: torneo_id }
            },
            // Agrega el nuevo ID al conjunto 'sub_admins'
            UpdateExpression: "ADD sub_admins :sub_admin_set", 
            ExpressionAttributeValues: {
                // El Set de DynamoDB se representa con 'SS' (String Set) o 'S' (String)
                ":sub_admin_set": { SS: [sub_admin_id] }, 
                ":max_count": { N: String(MAX_SUB_ADMINS) }
            },
            //  Solo permite la actualización si el conjunto
            // 'sub_admins' es nulo O si su tamaño es menor al límite (2).
            ConditionExpression: "attribute_not_exists(sub_admins) OR size(sub_admins) < :max_count",
            ReturnValues: "ALL_NEW"
        };

        const command = new UpdateItemCommand(updateParams);
        
        try {
            const result = await client.send(command);

            return {
                statusCode: 200,
                body: JSON.stringify({
                    message: `Subadministrador ${sub_admin_id} añadido exitosamente al torneo ${torneo_id}.`,
                    new_sub_admins: result.Attributes.sub_admins.SS // Devuelve la nueva lista
                })
            };
        } catch (error) {
            // Manejar la excepción específica cuando la condición falla (límite excedido)
            if (error.name === 'ConditionalCheckFailedException') {
                return {
                    statusCode: 403,
                    body: JSON.stringify({ 
                        message: `Límite de subadministradores alcanzado. El torneo ${torneo_id} ya tiene el máximo de ${MAX_SUB_ADMINS} subadministradores.`,
                    })
                };
            }
            throw error; // Relanzar cualquier otro error
        }

    } catch (error) {
        console.error("Error al añadir subadministrador:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ 
                message: "Error interno del servidor", 
                error: error.message 
            })
        };
    }
};