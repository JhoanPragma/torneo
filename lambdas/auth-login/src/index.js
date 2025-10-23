const { CognitoIdentityProviderClient, InitiateAuthCommand } = require("@aws-sdk/client-cognito-identity-provider");

const REGION = process.env.AWS_REGION || 'us-east-1';
const CLIENT_ID = process.env.COGNITO_CLIENT_ID; // Capturado de la variable de entorno

const cognitoClient = new CognitoIdentityProviderClient({ region: REGION });

/**
 * Handler de la función Lambda para el inicio de sesión del usuario.
 * Utiliza el flujo 'USER_PASSWORD_AUTH' de Cognito para autenticar y obtener tokens.
 */
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
            AuthFlow: 'USER_PASSWORD_AUTH', // Flujo para autenticar con nombre de usuario y contraseña
            ClientId: CLIENT_ID,
            AuthParameters: {
                USERNAME: email,
                PASSWORD: password,
            },
        };

        const command = new InitiateAuthCommand(params);
        const response = await cognitoClient.send(command);

        // Los tokens (ID Token y Access Token) son críticos para la autorización en API Gateway.
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: "Inicio de sesión exitoso.",
                id_token: response.AuthenticationResult.IdToken,
                access_token: response.AuthenticationResult.AccessToken,
                expires_in: response.AuthenticationResult.ExpiresIn,
                token_type: response.AuthenticationResult.TokenType
            })
        };

    } catch (error) {
        console.error("Error en el inicio de sesión:", error);
        
        let errorMessage = "Error al iniciar sesión. Verifique credenciales o confirme su cuenta.";
        
        // Manejo de errores comunes de Cognito
        if (error.name === 'NotAuthorizedException' || error.name === 'UserNotFoundException') {
            errorMessage = "Credenciales incorrectas o el usuario no existe/no está confirmado.";
        }

        return {
            statusCode: 401,
            body: JSON.stringify({ message: errorMessage, error: error.message })
        };
    }
};