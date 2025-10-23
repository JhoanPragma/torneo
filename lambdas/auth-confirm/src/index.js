const { CognitoIdentityProviderClient, ConfirmSignUpCommand } = require("@aws-sdk/client-cognito-identity-provider");
const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");

const REGION = process.env.AWS_REGION || 'us-east-1';
const CLIENT_ID = process.env.COGNITO_CLIENT_ID;
const USER_PROFILES_TABLE = process.env.USER_PROFILES_TABLE;
const DEFAULT_ROLE = "PARTICIPANTE"; // Rol por defecto

const cognitoClient = new CognitoIdentityProviderClient({ region: REGION });
const dbClient = new DynamoDBClient({ region: REGION });

exports.handler = async (event) => {
    try {
        const { email, code } = JSON.parse(event.body);

        if (!email || !code) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Email y código de confirmación son obligatorios." })
            };
        }

        // 1. Confirmar usuario en Cognito
        const confirmParams = {
            ClientId: CLIENT_ID,
            Username: email,
            ConfirmationCode: code
        };

        const confirmCommand = new ConfirmSignUpCommand(confirmParams);
        await cognitoClient.send(confirmCommand);
        
        // 2. Registrar perfil inicial en la tabla DynamoDB
        const putItemParams = {
            TableName: USER_PROFILES_TABLE,
            Item: {
                // Usamos el email como ID (Hash Key) para la tabla UserProfiles
                id: { S: email }, 
                email: { S: email },
                role: { S: DEFAULT_ROLE }, // Asignar el rol inicial
                created_at: { S: new Date().toISOString() }
            }
        };

        const putItemCommand = new PutItemCommand(putItemParams);
        await dbClient.send(putItemCommand);

        return {
            statusCode: 200,
            body: JSON.stringify({ 
                message: `Usuario confirmado y perfil inicial registrado con rol ${DEFAULT_ROLE}. Ahora puedes iniciar sesión.` 
            })
        };
    } catch (error) {
        console.error("Error en la confirmación o registro de perfil:", error);
        // Devolver un error más específico si es posible
        let errorMessage = "Error al confirmar el usuario y registrar perfil";
        if (error.name === 'UsernameExistsException') {
            errorMessage = "El usuario ya ha sido confirmado previamente.";
        }

        return {
            statusCode: 500,
            body: JSON.stringify({ message: errorMessage, error: error.message })
        };
    }
};