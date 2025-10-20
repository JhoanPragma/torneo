const { CognitoIdentityProviderClient, SignUpCommand } = require("@aws-sdk/client-cognito-identity-provider");

const REGION = process.env.AWS_REGION || 'us-east-1';
const CLIENT_ID = process.env.COGNITO_CLIENT_ID;

const cognitoClient = new CognitoIdentityProviderClient({ region: REGION });

exports.handler = async (event) => {
    try {
        const { email, password } = JSON.parse(event.body);

        if (!email || !password) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Email y contraseña son obligatorios." })
            };
        }

        const params = {
            ClientId: CLIENT_ID,
            Username: email,
            Password: password,
            UserAttributes: [{ Name: "email", Value: email }]
        };

        const command = new SignUpCommand(params);
        await cognitoClient.send(command);

        return {
            statusCode: 201,
            body: JSON.stringify({
                message: "Usuario registrado exitosamente. Por favor, revisa tu email para el código de confirmación o usa el endpoint /confirm."
            })
        };
    } catch (error) {
        console.error("Error en el registro:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Error al registrar el usuario", error: error.message })
        };
    }
};