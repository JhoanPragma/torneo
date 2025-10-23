const { DynamoDBClient, PutItemCommand, GetItemCommand, UpdateItemCommand } = require("@aws-sdk/client-dynamodb"); // <-- Nuevos comandos importados
const { v4: uuidv4 } = require('uuid');

const REGION = process.env.AWS_REGION || 'us-east-1';
const SALES_TABLE_NAME = process.env.TABLE_NAME || 'Ventas';
const TOURNAMENTS_TABLE_NAME = process.env.TOURNAMENTS_TABLE_NAME || 'Torneos'; // <-- Asumiendo nueva ENV VAR
const SALES_STAGES_TABLE_NAME = process.env.SALES_STAGES_TABLE || 'EtapasVenta'; // <-- Asumiendo nueva ENV VAR

const client = new DynamoDBClient({ region: REGION });

const COMISION_PORCENTAJE = 0.05; // 5% de comisión por cargo y servicio
const DEFAULT_MAX_CAPACITY = 1000; // Capacidad máxima por defecto si no se encuentra en Torneos

// =========================================================
// FUNCIÓN DE LÓGICA DE NEGOCIO: Etapas de Venta
// =========================================================
/**
 * Simula la lógica de búsqueda del precio de la etapa de venta activa 
 * basándose en la fecha actual. Reemplaza el precio_unitario del request.
 * NOTA: Esta función es un placeholder, requiere la tabla SalesStages real.
 */
const getCurrentPrice = async (torneoId) => {
    // 1. Simular la consulta a la tabla SALES_STAGES_TABLE_NAME
    // La consulta buscaría la etapa de venta donde: 
    // fecha_inicio <= NOW() AND fecha_fin >= NOW()
    
    // Por simplicidad, se retorna un precio hardcodeado/simulado:
    console.log(`Buscando etapa de venta activa para el torneo: ${torneoId}`);
    
    // En una implementación real, aquí se usaría un QueryCommand
    // const priceData = await client.send(new QueryCommand(params)); 
    
    // Por ahora, se simula que el precio unitario siempre es 50.00 si existe la etapa.
    return 50.00; 
};

/**
 * Handler de la función Lambda para procesar la venta de tickets.
 * 1. Valida Aforo (Capacidad).
 * 2. Calcula el precio final con la comisión (basado en Etapas de Venta).
 * 3. Registra la venta en DynamoDB.
 */
exports.handler = async (event) => {
    try {
        const body = JSON.parse(event.body);
        const { user_id, torneo_id, cantidad_tickets, precio_unitario } = body; // precio_unitario se ignorará/validará

        // Validaciones de entrada
        if (!user_id || !torneo_id || !cantidad_tickets) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Datos de venta incompletos (user_id, torneo_id, cantidad_tickets son obligatorios)." })
            };
        }

        // 1. OBTENER PRECIO UNITARIO DINÁMICO (Lógica de Etapas de Venta)
        const currentPrice = await getCurrentPrice(torneo_id);
        if (!currentPrice || currentPrice <= 0) {
            return {
                statusCode: 404,
                body: JSON.stringify({ message: "No se encontró una etapa de venta activa o el precio es cero." })
            };
        }

        // 2. VALIDACIÓN DE AFORO (Consumo Atómico en tabla Torneos)
        // Se asume que en la tabla 'Torneos' el campo 'participantes' es el contador de cupos.
        const newTotalParticipants = cantidad_tickets; // Usamos la cantidad de tickets como incremento

        const updateTournamentParams = {
            TableName: TOURNAMENTS_TABLE_NAME, 
            Key: { id: { S: torneo_id } },
            // Incrementamos atomicamente el contador 'participantes'
            UpdateExpression: "SET participantes = if_not_exists(participantes, :zero) + :inc",
            ExpressionAttributeValues: {
                ':inc': { N: String(newTotalParticipants) },
                ':zero': { N: '0' },
                // Se asume que 'capacidad_maxima' existe en el torneo
                ':max_cap': { N: String(DEFAULT_MAX_CAPACITY) } 
            },

            ReturnValues: 'ALL_NEW'
        };

        try {
            await client.send(new UpdateItemCommand(updateTournamentParams));
            // Si llega aquí, el cupo se consumió o no había límite estricto impuesto en DynamoDB.
        } catch (error) {
            // Manejo de error si el límite se excede (ConditionalCheckFailedException)
            console.error("Error al consumir el aforo:", error);
            if (error.name === 'ConditionalCheckFailedException') {
                return {
                    statusCode: 403,
                    body: JSON.stringify({ message: "Aforo completo. No hay cupos disponibles para este torneo." })
                };
            }
            throw error;
        }

        // 3. PROCESAR VENTA (Calcula comisión y registra)
        const precio_subtotal = cantidad_tickets * currentPrice;
        const comision = precio_subtotal * COMISION_PORCENTAJE;
        const precio_total = precio_subtotal + comision;

        const ventaId = uuidv4();
        const accessCode = uuidv4().substring(0, 8); // Código único para acceso al evento

        const params = {
            TableName: SALES_TABLE_NAME,
            Item: {
                id: { S: ventaId },
                user_id: { S: user_id },
                torneo_id: { S: torneo_id },
                cantidad_tickets: { N: String(cantidad_tickets) },
                precio_total: { N: precio_total.toString() },
                comision: { N: comision.toString() },
                access_code: { S: accessCode },
                fecha_compra: { S: new Date().toISOString() }
            }
        };

        await client.send(new PutItemCommand(params));

        return {
            statusCode: 201,
            body: JSON.stringify({
                message: "Venta de tickets completada exitosamente. Aforo consumido.",
                venta_id: ventaId,
                precio_unitario_final: currentPrice,
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