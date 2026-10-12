using Microsoft.AspNetCore.Mvc;

namespace DeploymentNetCore.Controllers
{
	[ApiController]
	[Route("[controller]")]
	public class HealthCheckController : ControllerBase
	{
		[HttpGet(Name = "HealthCheck")]
		public ActionResult Get()
		{
			if (true)
			{
				Console.WriteLine("test");
			}
            return Ok();
        }
    }
}
//testing tabs 6