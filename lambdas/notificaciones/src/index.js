const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");
const { DynamoDBClient, UpdateItemCommand } = require("@aws-sdk/client-dynamodb");

const REGION = process.env.AWS_REGION || 'us-east-1';
const SNS_TOPIC_ARN = process.env.SNS_TOPIC_ARN;
const TRANSMISSION_TABLE_NAME = process.env.TRANSMISSION_TABLE_NAME || 'Transmisiones';
const snsClient = new SNSClient({ region: REGION });
const dbClient = new DynamoDBClient({ region: REGION });

/**
 * Handler de la función Lambda para gestionar alertas y notificaciones.
 * Envía notificaciones a través de SNS y gestiona el bloqueo de enlaces.
 */
exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { tipo_alerta, id_evento, mensaje, url_enlace } = body;

        // Validaciones de entrada
        if (!tipo_alerta || !id_evento) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Tipo de alerta e ID de evento son obligatorios." })
            };
        }

        // Lógica para enviar notificaciones a los participantes y espectadores
        if (tipo_alerta === 'actualizacion_torneo') {
            if (!mensaje) {
                return {
                    statusCode: 400,
                    body: JSON.stringify({ message: "Se requiere un mensaje para las notificaciones." })
                };
            }

            const publishParams = {
                TopicArn: SNS_TOPIC_ARN,
                Message: mensaje,
                Subject: `Actualización del Torneo: ${id_evento}`
            };

            await snsClient.send(new PublishCommand(publishParams));

            return {
                statusCode: 200,
                body: JSON.stringify({ message: `Notificación enviada para el evento ${id_evento}.` })
            };
        }

        // Lógica para bloquear un enlace en caso de irregularidades
        if (tipo_alerta === 'bloqueo_enlace') {
            if (!url_enlace) {
                return {
                    statusCode: 400,
                    body: JSON.stringify({ message: "Se requiere una URL para bloquear el enlace." })
                };
            }

            const updateParams = {
                TableName: TRANSMISSION_TABLE_NAME,
                Key: {
                    id: { S: id_evento }
                },
                UpdateExpression: "SET estado = :estado, url_enlace = :url_enlace",
                ExpressionAttributeValues: {
                    ":estado": { S: "bloqueado" },
                    ":url_enlace": { S: "Enlace bloqueado debido a irregularidades." }
                }
            };

            await dbClient.send(new UpdateItemCommand(updateParams));

            return {
                statusCode: 200,
                body: JSON.stringify({ message: `Enlace bloqueado para el evento ${id_evento}.` })
            };
        }

        return {
            statusCode: 400,
            body: JSON.stringify({ message: "Tipo de alerta no reconocido." })
        };

    } catch (error) {
        console.error("Error en el servicio de notificaciones:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Error interno del servidor", error: error.message })
        };
    }
};