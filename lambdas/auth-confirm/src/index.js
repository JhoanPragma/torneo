const { CognitoIdentityProviderClient, ConfirmSignUpCommand } = require("@aws-sdk/client-cognito-identity-provider");

const REGION = process.env.AWS_REGION || 'us-east-1';
const CLIENT_ID = process.env.COGNITO_CLIENT_ID;

const cognitoClient = new CognitoIdentityProviderClient({ region: REGION });

exports.handler = async (event) => {
    try {
        const { email, code } = JSON.parse(event.body);

        if (!email || !code) {
            return {
                statusCode: 400,
                body: JSON.stringify({ message: "Email y código de confirmación son obligatorios." })
            };
        }

        const params = {
            ClientId: CLIENT_ID,
            Username: email,
            ConfirmationCode: code
        };

        const command = new ConfirmSignUpCommand(params);
        await cognitoClient.send(command);

        return {
            statusCode: 200,
            body: JSON.stringify({ message: "Usuario confirmado exitosamente. Ahora puedes iniciar sesión." })
        };
    } catch (error) {
        console.error("Error en la confirmación:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ message: "Error al confirmar el usuario", error: error.message })
        };
    }
};