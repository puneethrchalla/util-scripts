import com.amazonaws.auth.DefaultAWSCredentialsProviderChain;
import com.amazonaws.services.securitytoken.AWSSecurityTokenService;
import com.amazonaws.services.securitytoken.AWSSecurityTokenServiceClientBuilder;
import com.amazonaws.services.securitytoken.model.GetCallerIdentityRequest;
import com.amazonaws.services.securitytoken.model.GetCallerIdentityResponse;

public class STSCallerIdentity {
    public static void main(String[] args) {
        // Create an STS client using the default credentials provider chain
        AWSSecurityTokenService sts = AWSSecurityTokenServiceClientBuilder.standard()
                .withCredentials(DefaultAWSCredentialsProviderChain.getInstance())
                .build();

        // Create a request to get the caller's identity
        GetCallerIdentityRequest request = new GetCallerIdentityRequest();

        // Get the caller's identity
        GetCallerIdentityResponse response = sts.getCallerIdentity(request);

        // Display the caller's identity information
        System.out.println("Account ID: " + response.getAccount());
        System.out.println("User ARN: " + response.getArn());
        System.out.println("User ID: " + response.getUserId());
    }
}