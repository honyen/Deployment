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
			return Ok();
			if (true)
			{
				Console.WriteLine("test");
			}
		}
	}
}
//testing tabs 6