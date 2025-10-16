const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { DynamoDBClient, UpdateItemCommand } = require("@aws-sdk/client-dynamodb");
const QRCode = require('qrcode');
const { v4: uuidv4 } = require('uuid');

const REGION = process.env.AWS_REGION || 'us-east-1';
const BUCKET_NAME = process.env.BUCKET_NAME || 'tournament-qr-codes';
const TABLE_NAME = process.env.TABLE_NAME || 'Ventas';
const s3Client = new S3Client({ region: REGION });
const dbClient = new DynamoDBClient({ region: REGION });

/**
 * Handler de la función Lambda para generar y subir códigos QR.
 * @param {object} event - Objeto de evento con los datos de la transacción.
 */
exports.handler = async (event) => {
    console.log("Evento recibido para generar QR:", JSON.stringify(event, null, 2));

    try {
        const { id_transaccion, url_acceso } = event;

        if (!id_transaccion || !url_acceso) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "ID de transacción y URL de acceso son obligatorios." })
            };
        }

        const qrCodeBuffer = await QRCode.toBuffer(url_acceso, { type: 'png' });
        const qrKey = `qr/${id_transaccion}.png`;

        // Sube la imagen del QR a S3
        const s3Params = {
            Bucket: BUCKET_NAME,
            Key: qrKey,
            Body: qrCodeBuffer,
            ContentType: 'image/png'
        };

        await s3Client.send(new PutObjectCommand(s3Params));
        const qrUrl = `https://${BUCKET_NAME}.s3.amazonaws.com/${qrKey}`;

        // Actualiza el registro de la venta en DynamoDB con la URL del QR
        const dbParams = {
            TableName: TABLE_NAME,
            Key: {
                id: { S: id_transaccion }
            },
            UpdateExpression: "SET qr_url = :qrUrl",
            ExpressionAttributeValues: {
                ":qrUrl": { S: qrUrl }
            }
        };

        await dbClient.send(new UpdateItemCommand(dbParams));

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: "Código QR generado y almacenado exitosamente.",
                qr_url: qrUrl
            })
        };
    } catch (error) {
        console.error("Error al generar o subir el QR:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Error interno del servidor", error: error.message })
        };
    }
};