const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");
const { v4: uuidv4 } = require('uuid');

const REGION = process.env.AWS_REGION || 'us-east-1';
const TABLE_NAME = process.env.TABLE_NAME || 'Ventas';
const client = new DynamoDBClient({ region: REGION });

const COMISION_PORCENTAJE = 0.05; // 5% de comisión por cargo y servicio

/**
 * Handler de la función Lambda para procesar la venta de tickets.
 * Calcula el precio final con la comisión y registra la venta en DynamoDB.
 */
exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { user_id, torneo_id, cantidad_tickets, precio_unitario } = body;

        // Validaciones de entrada
        if (!user_id || !torneo_id || !cantidad_tickets || !precio_unitario) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Datos de venta incompletos." })
            };
        }

        const precio_subtotal = cantidad_tickets * precio_unitario;
        const comision = precio_subtotal * COMISION_PORCENTAJE;
        const precio_total = precio_subtotal + comision;

        const ventaId = uuidv4();
        const accessCode = uuidv4().substring(0, 8); // Código único para acceso al evento

        const params = {
            TableName: TABLE_NAME,
            Item: {
                id: { S: ventaId },
                user_id: { S: user_id },
                torneo_id: { S: torneo_id },
                cantidad_tickets: { N: cantidad_tickets.toString() },
                precio_total: { N: precio_total.toString() },
                comision: { N: comision.toString() },
                access_code: { S: accessCode },
                fecha_compra: { S: new Date().toISOString() }
            }
        };

        const command = new PutItemCommand(params);
        await client.send(command);

        return {
            statusCode: 201,
            body: JSON.stringify({
                message: "Venta de tickets completada exitosamente.",
                venta_id: ventaId,
                precio_final: precio_total,
                acceso_evento: accessCode
            })
        };
    } catch (error) {
        console.error("Error al procesar la venta:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Error interno del servidor", error: error.message })
        };
    }
};