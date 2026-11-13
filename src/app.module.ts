import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { DatabaseModule } from './database/database.module.js';

@Module({
  imports: [
    // Loads .env (the same file docker compose uses) and makes ConfigService global.
    ConfigModule.forRoot({ isGlobal: true, cache: true }),
    DatabaseModule,
    // Feature modules register only the entities they own, e.g. inside the trips module:
    // TypeOrmModule.forFeature([Ride, RidePassenger, Rating])
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
